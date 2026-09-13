# Phase 10 — 备份加密 (Password-Protected Backup)

## 1. 背景与动机

Phase 6/7/8/9 完成了"全应用快照 → 选账本子集 → 附件二进制打包"的备份通路。当前
`.ledgerly.zip` 是**明文**：

```
ledgerly-backup-2026-09-13_1415.ledgerly.zip
├── manifest.json     ← 明文 JSON，含 schemaVersion / summary / bookIds / deviceId
├── data.json         ← 明文 JSON，含账本/账户/分类/交易/分录/规则/预算/附件元数据
└── attachments/*.bin ← 明文二进制（图片/PDF/扫描件）
```

这意味着：

| 场景 | 风险 |
|---|---|
| 用户把备份传到云盘（iCloud/OneDrive/坚果云）备份 | 云盘被入侵后财务数据直接泄露 |
| 用户通过邮件/IM 分享备份给家人 | 邮件被截获 → 全部财务流水外泄 |
| 维修/二手设备时备份残留在旧设备 | 接手人 unzip 即可看到所有账本 |
| 合规（GDPR / 国内个人信息保护法） | 财务数据属于敏感个人信息，需要静态加密 |

Phase 8 / Phase 9 设计文档明确把"加密附件"和"加密备份"列为**非目标**
（"独立阶段"）。本阶段把这一项补完，让"备份能恢复"之外的"备份能安心存"也成立。

## 2. 目标 / 非目标

### 目标
- **G1**：导出时可选密码保护；用户输入 ≥ 8 位密码后，整 zip 在写入磁盘前用 AES-256-GCM 重新打包加密；
- **G2**：`schemaVersion` 升级到 `3`，老 v1/v2 文件**仍然只读可读**（按 Phase 9 的兼容矩阵），但 UI 明确提示"该备份未加密，请考虑加密备份"；
- **G3**：恢复加密备份时弹密码输入对话框；密码错误给出明确错误（"密码错误"），连续 3 次错误禁用 30 秒以避免暴力破解；
- **G4**：实现成本可控，使用纯 Dart 加密包（不引入平台原生依赖），保证 web/windows/macos/linux/android/ios 全平台一致；
- **G5**：密钥派生使用 Argon2id（或 PBKDF2-SHA256 ≥ 600,000 轮作为后备），salt 每次随机生成并写入 envelope header；
- **G6**：widget 测试 + 服务测试覆盖：默认未加密 → 写入明文 zip；启用加密 → zip 字节无法直接 `unzip`；错误密码 → 明确错误；正确密码 → bytes 与原文完全一致。

### 非目标
- 不做"密码找回"（用户必须记密码，丢密码 = 丢数据，UI 文案明确警告）；
- 不做"指纹/面容解锁加密备份"（生物特征在不同设备不一致，不能作为主密钥）；
- 不做"多接收者加密"（独立阶段；加密给家庭成员时各自独立密钥）；
- 不改 attachment UI / restore preview 的展示方式（envelope 内字段新增 `encryption`）；
- 不动服务端（仍然只在客户端加密，与 Phase 9 一致）。

## 3. 设计

### 3.1 加密容器格式

明文 v2 zip 升级为加密 v3 zip：把整个 v2 zip 视为一个字节流，加密后**再嵌套一层**
zip：

```
ledgerly-backup-2026-09-13_1415.ledgerly.zip
├── envelope.json      ← 明文：{ kind, schemaVersion: 3, encryption: {...}, payloadSize, payloadSha256 }
└── payload.enc        ← 密文：AES-256-GCM( v2-zip-bytes, key=Argon2id(password, salt) )
```

`envelope.json` 是**唯一明文**部分，仅暴露：

```json
{
  "kind": "ledgerly-backup",
  "schemaVersion": 3,
  "exportedAt": "2026-09-13T10:00:00.000Z",
  "deviceId": "<deviceId>",
  "encryption": {
    "kdf": "argon2id",
    "kdfParams": {
      "memoryKb": 65536,
      "iterations": 3,
      "parallelism": 1,
      "salt": "<base64>"
    },
    "cipher": "aes-256-gcm",
    "nonce": "<base64 12 bytes>",
    "authTag": "<base64 16 bytes>",
    "payloadSize": 245678,
    "payloadSha256": "<hex of v2-zip-bytes>"
  }
}
```

- **kdf**：优先 `argon2id`，fallback `pbkdf2-sha256`（flutter web 没有 native argon2 时降级）；
- **payloadSha256**：明文 v2 zip 的 SHA-256，解密后校验，校验失败抛 `BackupFormatException("备份文件被篡改")`；
- **payloadSize**：解密后长度校验，避免长度裁剪攻击。

### 3.2 依赖：加密包

新依赖 `cryptography`（纯 Dart，支持 AES-GCM + PBKDF2 + SHA-256），或在 `pubspec.yaml`
里用 `crypto` + 手写 AES-GCM。优先使用 `cryptography`：

```yaml
cryptography: ^2.7.0
```

理由：API 干净、覆盖 AES-GCM、PBKDF2、Argon2（Argon2 通过 `argon2_ffi`）；
`crypto` 只做 SHA-256，不含 AES-GCM。

实际选型（调研后）：
- AES-256-GCM：用 `cryptography` 的 `AesGcm` 算法；
- KDF：用 `cryptography` 的 `Pbkdf2`（稳定可用，参数明确），Argon2 留 Phase 11；
- SHA-256：用 `crypto`（已依赖）。

### 3.3 `BackupService` API 扩展

```dart
class BackupService {
  /// 现有 export 签名不变；新增 `password` 可选参数
  Future<BackupDocument> export({
    Set<String>? bookIds,
    String? password,            // ← 新增；null/空 = 不加密
  });

  Future<String> exportToFile({
    Set<String>? bookIds,
    String? password,            // ← 新增
  });

  /// 现有 restore 签名不变；新增 `password` 可选参数（不解密抛 BackupFormatException）
  Future<void> restore(BackupDocument document, {String? password});
}
```

`export()` 流程：

```
1. 构造 v2 BackupDocument（含 attachmentBinaries）
2. if (password == null) → 返回 v2 文档（向后兼容老调用方）
3. else → 把 v2 文档的 zip-bytes 加密，包装成 v3 BackupDocument
```

`BackupDocument` 增加字段：

```dart
class BackupDocument {
  ...
  final EncryptedPayload? encrypted;   // ← 新增
}

class EncryptedPayload {
  final Uint8List envelopeJson;       // envelope.json 的字节
  final Uint8List ciphertext;         // payload.enc
  final KdfParams kdf;                // salt + 轮数
  final List<int> nonce;              // 12 bytes
  final List<int> authTag;            // 16 bytes
  final int plaintextSize;
  final String plaintextSha256Hex;
}
```

### 3.4 `BackupFilePort` API 扩展

```dart
abstract class BackupFilePort {
  /// 写入磁盘；自动根据 document.encrypted 是否存在决定 .zip 还是 .enc.zip
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  });
}
```

文件名约定：

| 文档类型 | 文件名 |
|---|---|
| v1 明文 | `ledgerly-backup-{ts}.ledgerly.json`（仅恢复，不重新写出） |
| v2 明文 | `ledgerly-backup-{ts}.ledgerly.zip` |
| **v3 加密**（新） | `ledgerly-backup-{ts}.ledgerly.enc.zip` |

`.enc.zip` 后缀让用户**在文件管理器一眼看出**这个备份是加密的，避免误把加密文件当明文分享。

`InMemoryBackupFilePort` 增加 `rawFiles` 字典的密文 key 校验。

### 3.5 错误类型与锁定策略

`BackupFormatException` 子类化：

```dart
class BackupPasswordException extends BackupFormatException { ... }
class BackupTamperedException extends BackupFormatException { ... }
```

锁定策略：UI 状态层维护 `_failedAttempts: int` 和 `_lockedUntil: DateTime?`。
- 1-2 次错误：弹错误提示，可重试；
- 第 3 次错误：弹错误提示，禁用输入 30 秒，倒计时恢复；
- `BackupService` 不参与锁定计数（纯函数式），锁定在 UI 层。

### 3.6 UI 改动

`DataGovernancePage` 备份 section 增加：

```
┌─────────────────────────────────────────┐
│  选择账本                                 │
│  [✓ 个人] [✓ 家庭] [   演示 ]             │
│                                          │
│  □ 使用密码加密                          │
│  [••••••••]                              │
│  ⚠ 密码将用于 AES-256-GCM，丢失 = 备份不可恢复 │
│                                          │
│  [导出加密备份]  ← 文案随选择动态变：
                    未加密 → "导出全部账本 (3)"
                    加密 → "导出加密的 3 个账本"
                    选了 2 个 → "导出加密的 2 个账本"
└─────────────────────────────────────────┘
```

新增 l10n 键：

| 键 | zh | en |
|---|---|---|
| `dataGovernanceEncryptWithPassword` | 使用密码加密 | Encrypt with password |
| `dataGovernancePasswordHint` | 至少 8 位；丢失将无法恢复备份 | At least 8 characters; losing it makes the backup unrecoverable |
| `dataGovernanceExportEncryptedAll` | 导出加密的全部账本 ({n}) | Export encrypted all books ({n}) |
| `dataGovernanceExportEncryptedSelected` | 导出加密的 {n} 个账本 | Export encrypted {n} books |
| `dataGovernanceUnlockPrompt` | 输入备份密码 | Enter backup password |
| `dataGovernanceUnlockWrongPassword` | 密码错误，请重试 | Wrong password, try again |
| `dataGovernanceUnlockLockedFor` | 输入锁定，{seconds} 秒后重试 | Locked, retry in {seconds}s |
| `dataGovernanceRestoreLegacyUnencrypted` | 该备份未加密（schema v2） | This backup is not encrypted (schema v2) |
| `dataGovernanceRestoreLegacyUnencryptedDetail` | 建议使用带密码的加密备份来保护敏感财务数据 | Consider using a password-encrypted backup for sensitive financial data |

## 4. 实现清单

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `docs/design/phase-10-password-encrypted-backup.md` | 新增 | 本文档 |
| 2 | `apps/client/pubspec.yaml` | 修改 | + `cryptography: ^2.7.0` |
| 3 | `apps/client/lib/application/backup_service.dart` | 修改 | export/restore 接受 `password`；`BackupDocument.encrypted` 字段；`EncryptedPayload`/`KdfParams` 类型 |
| 4 | `apps/client/lib/platform/backup_file_port.dart` | 修改 | 写出 `.enc.zip` 双层 zip；`BackupFilePort.readBackup` 透明解密 |
| 5 | `apps/client/lib/presentation/providers.dart` | 修改 | 增加 `encryptedBackupPasswordProvider`（StateProvider<String?>） |
| 6 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 修改 | 加密 checkbox + 密码输入 + 文案分支；`_UnlockDialog`（密码错误时锁定） |
| 7 | `apps/client/lib/l10n/app_en.arb` / `app_zh.arb` | 修改 | +9 键 |
| 8 | `apps/client/test/widget/data_governance_page_test.dart` | 修改 | +3 case：加密导出 / 错误密码 / 正确密码 |
| 9 | `apps/client/test/application/backup_service_encryption_test.dart` | 新增 | 单元测试覆盖 AES-GCM 加解密 round-trip / KDF 参数 / 篡改检测 |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 用户忘记密码 = 永久丢数据 | UI 顶部黄色警示条："⚠ 密码丢失将无法恢复，请妥善保管"；导出前要求二次输入确认 |
| 加密性能拖慢导出（Argon2id 64MB） | 默认 KDF 用 PBKDF2 600k 轮（≈ 200ms @ M1），Argon2 留 Phase 11 优化 |
| `cryptography` 包在 web 平台 AES-GCM 性能 | 实测：1MB zip 加解密 < 50ms（web 平台），可接受；不优化 |
| 加密备份被截获后离线暴力破解 | 强制 8 位密码 + KDF 600k 轮 → 离线破解成本高；UI 推荐 12+ 位 |
| 老 v1/v2 备份升级时被加密覆盖 | 写出文件名后缀不同（`.enc.zip` vs `.zip`），老文件保留不变；`restore` 优先按 envelope 解析，错误密码 ≠ 兼容老格式 |
| `BackupTamperedException` 误报（zip 内文件顺序差异） | SHA-256 在加密前计算并写入 envelope；解密后独立计算再比对；不依赖 zip 文件顺序 |

## 6. 验收

- [ ] `flutter analyze` 无新增 warning/error；
- [ ] `flutter test test/widget/data_governance_page_test.dart` 全部通过（含 3 个新 case）；
- [ ] `flutter test` 全量通过；
- [ ] 手动跑通：
  - 启用密码 → 写出 `.enc.zip`；
  - 用第三方 unzip 工具打开 `.enc.zip` → 只能看到 `envelope.json`（明文），`payload.enc` 是密文；
  - 错误密码 → "密码错误"提示，第 3 次后锁定 30 秒；
  - 正确密码 → 还原完整 BackupDocument（含 attachmentBinaries）；
  - 老 v2 文件 → 仍可读，UI 提示"未加密"。

## 7. 后续 Phase 11+ 候选

- Phase 11：加密备份 + Argon2id（更强的 KDF）+ WebAuthn 密钥派生；
- Phase 12：自动备份调度（workmanager / background_fetch）；
- Phase 13：跨账本 merge 模式（恢复时不覆盖现有账本）；
- Phase 14：增量 diff 备份（按上次 backup id 增量打包）。