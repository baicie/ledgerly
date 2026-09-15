# Phase 11 — Argon2id 密钥派生

## 1. 背景与动机

Phase 10 落地了密码加密备份（AES-256-GCM + `.enc.zip`），但密钥派生用的是
PBKDF2-HMAC-SHA256（60 万轮）。GPU / ASIC 对 PBKDF2 的并行成本很低，离线
撞密码比内存困难函数便宜一个数量级。

Phase 10 设计把 Argon2id 明确留到本阶段：envelope 里已经记录了 `kdf.algorithm`，
解密路径按字段分支即可，不必升 schema。

## 2. 目标 / 非目标

### 目标

- **G1**：新导出的加密备份默认用 Argon2id（RFC 9106）派生 AES-256 密钥；
- **G2**：envelope 写入完整 KDF 参数（algorithm / memoryKb / iterations /
  parallelism / salt / hashLengthBytes），解密只信文件里的参数；
- **G3**：Phase 10 的 `pbkdf2-sha256` 文件仍然能解锁，行为与现在一致；
- **G4**：不引入 FFI / `argon2_ffi`：用 `cryptography` 自带的纯 Dart
  `Argon2id`，web / windows / macos / linux / android / ios 同一套；
- **G5**：未知 `algorithm` 拒绝解密（`BackupFormatException`），避免静默降级；
- **G6**：测试覆盖：默认 algorithm = argon2id；Argon2id round-trip；旧
  PBKDF2 envelope 仍可解密；未知 KDF 抛错。

### 非目标

- 不做 WebAuthn / 生物特征派生备份主密钥（跨设备密钥不一致，Phase 10 已排除）；
- 不改 `.enc.zip` 容器布局，不升 `schemaVersion`（仍为 3）；
- 不在 UI 增加 KDF 选择器（用户只看到密码框）；
- 不把生产级 19 MiB 参数用于测试（测试用 `BackupEncryption.testing()`）；
- 不动服务端。

## 3. 设计

### 3.1 默认参数

生产（非 web）对齐 OWASP 2023 Argon2id：

| 参数 | 值 | 说明 |
|---|---|---|
| memory | 19456 KiB（19 MiB） | 内存困难，限制 GPU 并行 |
| iterations | 2 | OWASP 建议 |
| parallelism | 1 | 移动设备友好 |
| hashLength | 32 | AES-256 |
| salt | 16 字节随机 | 每次导出重新生成 |

web 上纯 Dart Argon2id 更慢，默认 memory 降到 8192 KiB（8 MiB），仍写入
envelope，解密按文件参数走，跨端恢复不受影响。

测试构造器：

```dart
BackupEncryption.testing() // memory=32 KiB, iterations=1, parallelism=1
```

### 3.2 `KdfParams`

```dart
class KdfParams {
  final String algorithm;      // argon2id | pbkdf2-sha256
  final int iterations;
  final Uint8List salt;
  final int hashLengthBytes;
  final int memoryKb;          // argon2id 必填；pbkdf2 为 0
  final int parallelism;       // argon2id 用；pbkdf2 忽略
}
```

`toJson` / `fromJson` 向后兼容：Phase 10 文件没有 `memoryKb` /
`parallelism` 时，按 PBKDF2 解析（algorithm 缺省 `pbkdf2-sha256`）。

### 3.3 派生

```
switch (algorithm) {
  argon2id      → Argon2id(memory, parallelism, iterations, hashLength)
                    .deriveKey(secretKey: password, nonce: salt)
  pbkdf2-sha256 → Pbkdf2(Hmac.sha256, iterations, bits=256)
                    .deriveKey(secretKey: password, nonce: salt)
  other         → BackupFormatException('不支持的 KDF')
}
```

加密默认走 `argon2id`。调用方仍可传入 `KdfParams(algorithm: pbkdf2-sha256)`
做回归。

### 3.4 兼容矩阵

| 文件 | 解锁 |
|---|---|
| v1 `.ledgerly.json` | 明文，不走 KDF |
| v2 `.ledgerly.zip` | 明文，不走 KDF |
| v3 + `pbkdf2-sha256` | Phase 10 路径 |
| v3 + `argon2id` | 本阶段默认 |
| v3 + 未知 algorithm | 拒绝 |

## 4. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `docs/design/phase-11-argon2id-kdf.md` | 新增 |
| 2 | `apps/client/lib/application/backup_encryption.dart` | Argon2id 默认 + 分支派生 |
| 3 | `apps/client/test/application/backup_service_encryption_test.dart` | 新断言 + 兼容用例 |
| 4 | `apps/client/test/widget/data_governance_page_test.dart` | 改用 `.testing()` |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 19 MiB Argon2id 拖慢低端机导出 | 只在用户勾选加密时运行；web 降到 8 MiB |
| 测试套件被生产参数拖死 | 强制测试走 `.testing()`（32 KiB） |
| 旧备份打不开 | 解密只读 envelope，PBKDF2 分支保留 |
| 纯 Dart Argon2 与 native 实现字节不一致 | 加解密都用同一 `cryptography` 实现，不混 FFI |

## 6. 验收

- [x] `flutter analyze` 无新增 warning/error；
- [x] `flutter test test/application/backup_service_encryption_test.dart` 通过；
- [x] `flutter test test/widget/data_governance_page_test.dart` 通过；
- [x] 新加密 envelope 的 `kdf.algorithm` 为 `argon2id`；
- [x] Phase 10 PBKDF2 envelope 仍能 `unlockEncrypted`。

## 7. 后续候选

- Phase 12：打开应用时的自动备份调度（见 [phase-12-auto-backup.md](./phase-12-auto-backup.md)）；
- Phase 13：跨账本 merge 模式；
- Phase 14：增量 diff 备份；
- 以后再评估 WebAuthn PRF（仅 web，且不能作为跨设备主密钥）。
