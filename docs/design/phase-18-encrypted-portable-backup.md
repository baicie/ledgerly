# Phase 18 — 加密便携备份

## 1. 背景与动机

Phase 16 可以把基础全量和最新增量合成为独立全量文件，但产物始终是明文
`.ledgerly.zip`。当用户需要把便携备份通过网盘、邮件或聊天工具分享时，
备份中会直接暴露账本、流水和附件内容。

Phase 10/11 已经提供 AES-256-GCM + Argon2id 的密码加密容器。本阶段让
便携化流程可选复用该容器，生成独立的 `.ledgerly.enc.zip`。

## 2. 目标 / 非目标

### 目标

- **G1**：`BackupService.consolidateLatest()` 增加可选 `password`；
- **G2**：留空密码继续生成 Phase 16 明文便携备份；
- **G3**：填写密码时使用现有 Argon2id + AES-256-GCM 容器加密；
- **G4**：加密产物使用新的 `backupId`，登记为手工加密备份；
- **G5**：明文合成更新 metadata 的 last/base；加密合成只更新 last；
- **G6**：删除旧 base/delta 后，加密产物仍可用密码独立恢复；
- **G7**：错误密码无法恢复或预览该文件；
- **G8**：数据治理页在便携化前弹出可选密码对话框，非空密码至少 8 位。

### 非目标

- 不自动上传或托管加密备份；
- 不改变既有 `.ledgerly.enc.zip` 文件格式；
- 不删除旧的 base/delta，清理仍由 Phase 15 显式执行；
- 不把当前数据库尚未进入最近增量的改动混入快照；
- 不保存用户密码或提供密码找回。

## 3. API

```dart
Future<BackupConsolidationResult?> consolidateLatest({
  String? password,
});
```

- `password == null` 或空字符串：生成明文 `.ledgerly.zip`；
- 非空 `password`：生成加密 `.ledgerly.enc.zip`；
- 非空密码少于 8 位时由 `BackupEncryption` 拒绝；
- 最近备份不是未加密增量时返回 `null`。

## 4. 流程

```text
metadata.lastBackupPath
  -> readBackup
  -> require isIncremental && !isEncrypted
  -> _materializeIncremental(base + delta)
  -> assign new backupId
  -> optional encrypt(v2 zip bytes)
  -> write .ledgerly.zip / .ledgerly.enc.zip
  -> metadata.record(encrypted: ...)
  -> catalog(manual, full/encrypted)
```

### metadata 语义

明文便携备份可以作为后续增量基线，因此 `BackupMetadataStore.record()`
会更新 last 和 base。

加密便携备份不适合作为增量基线，因为增量恢复要求可无密码读取基础文件。
`record(encrypted: true)` 只更新 last，不覆盖已有 base；后续增量继续依赖
原来的明文基础全量。

## 5. UI

最近一次备份为增量时，操作区显示“生成便携备份”。点击后打开密码对话框：

- 密码留空：确认后生成明文便携备份；
- 密码非空：必须至少 8 位，并与确认框一致；
- 取消：不写文件，也不修改 metadata/catalog。

成功后复用现有成功提示，并刷新 status card、分享入口和备份目录。

## 6. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_service.dart` | 可选密码、统一加密封装、metadata 语义 |
| 2 | `data_governance_page.dart` | 可选密码对话框与提交 |
| 3 | l10n ARB | 对话框标题、说明和字段 |
| 4 | `backup_consolidation_test.dart` | 加密独立恢复、错误密码、base 保护 |
| 5 | `data_governance_page_test.dart` | 明文/加密 UI 路径与密码校验 |
| 6 | 文档索引和路线图 | Phase 18 |

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 用户输错密码导致无法恢复 | 密码和确认框必须一致，且不保存密码 |
| 加密产物误替换增量 base | `record(encrypted: true)` 不更新 base |
| 加密产物缺少新备份 ID | 先分配新 ID，再执行加密封装 |
| 旧 base/delta 被删除后无法验证 | 测试直接删除原文件后用密码恢复 |
| 明文兼容路径被破坏 | 现有 Phase 16 测试继续覆盖 |

## 8. 验收

- [x] 明文便携备份行为保持兼容；
- [x] 密码非空时生成独立加密便携备份；
- [x] 加密产物的 last 更新且 base 保持原明文全量；
- [x] catalog 记录 manual + encrypted；
- [x] 删除旧 base/delta 后密码恢复成功；
- [x] 错误密码不可恢复；
- [x] UI 支持留空、短密码拦截和加密提交；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（392/392）。
