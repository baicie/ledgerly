# Phase 21 — 加密备份密码轮换

## 1. 背景与动机

Phase 10–20 已支持创建、恢复、演练和管理加密备份，但用户更改备份密码时
只能重新导出一份备份。已有历史加密文件无法在不恢复数据的情况下更换密码，
而且加密导出的文件名只精确到分钟，同一分钟内可能覆盖同名文件。

本阶段提供安全的加密备份密码轮换，并保证旧文件不被覆盖。

## 2. 目标 / 非目标

### 目标

- **G1**：为指定加密 catalog artifact 提供密码轮换 API；
- **G2**：旧密码错误时拒绝操作并保留原文件；
- **G3**：使用新密码重新执行 Argon2id + AES-256-GCM 封装；
- **G4**：新文件使用新的 `backupId`，登记为手工加密备份；
- **G5**：原文件继续保留，可继续用旧密码恢复；
- **G6**：只有轮换当前 latest 时才更新 metadata 的 last；
- **G7**：历史加密文件轮换不改变当前 latest/base；
- **G8**：文件名包含 backupId 后缀，避免同分钟覆盖；
- **G9**：数据治理页提供旧密码、新密码和确认新密码对话框。

### 非目标

- 不找回或重置已丢失的密码；
- 不自动删除旧密码文件；
- 不把密码保存到系统密钥链；
- 不改变备份 JSON/zip schema；
- 不轮换未加密备份；
- 不同时批量轮换多个加密文件。

## 3. API

```dart
class BackupPasswordRotationResult {
  final String path;
  final String sourcePath;
  final String backupId;
  final int sizeBytes;
  final bool updatedLatest;
}

Future<BackupPasswordRotationResult> rotateCatalogBackupPassword(
  BackupArtifact artifact, {
  required String oldPassword,
  required String newPassword,
});
```

新密码少于 8 位时抛出 `ArgumentError`；旧密码错误时抛出
`BackupPasswordException`。

## 4. 流程

```text
catalog encrypted artifact
  -> read encrypted outer container
  -> decrypt with old password
  -> validate recoverable document
  -> assign new backupId
  -> encrypt with new password
  -> write new .ledgerly.enc.zip
  -> catalog(manual, encrypted)
  -> if source is latest: metadata.record(encrypted)
```

加密增量若存在，会先合成为独立全量后再重封装，确保新文件可独立恢复。

## 5. 文件命名

原有名称：

```text
ledgerly-backup-YYYY-MM-DD_HHmm.ledgerly.enc.zip
```

新名称加入 backupId 前 8 位：

```text
ledgerly-backup-YYYY-MM-DD_HHmm-<backupId8>.ledgerly.enc.zip
```

这样即使导出和轮换发生在同一分钟，也不会覆盖原文件。

## 6. UI

加密目录项菜单增加“更改密码”，对话框包含：

- 旧密码；
- 新密码；
- 确认新密码；
- 取消 / 更改密码。

旧密码错误沿用解锁失败计数和临时锁定策略。成功后刷新 metadata/catalog，
并提示新文件路径与大小。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_service.dart` | 轮换 API、新 backupId、metadata 语义 |
| 2 | `backup_file_port.dart` | backupId 文件名后缀 |
| 3 | `data_governance_page.dart` | 轮换菜单和三字段对话框 |
| 4 | l10n ARB | 轮换文案 |
| 5 | `backup_catalog_test.dart` | 旧文件保留、latest/historical、错误密码 |
| 6 | `backup_file_port_test.dart` | 同分钟文件不覆盖 |
| 7 | `data_governance_page_test.dart` | 轮换 UI 与 metadata 更新 |
| 8 | 文档索引和路线图 | Phase 21 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 新文件覆盖旧文件 | 文件名加入 backupId 后缀 |
| 轮换失败破坏旧文件 | 只读旧文件，先加密成功再写新文件 |
| 历史轮换误改 latest | 仅路径等于 metadata.lastBackupPath 时更新 |
| 新密码输入错误无法恢复 | 新密码与确认框必须一致 |
| 旧密码错误被误判为数据损坏 | 保留 `BackupPasswordException` 和锁定提示 |
| latest 仍指向旧密码文件 | 当前 latest 轮换后更新 last 到新文件 |

## 9. 验收

- [x] 加密目录项可使用旧密码和新密码轮换；
- [x] 新文件使用新 backupId 并登记为手工加密备份；
- [x] 原文件保留且仍可使用旧密码恢复；
- [x] 新文件可使用新密码独立恢复；
- [x] 旧密码错误和短新密码被拒绝；
- [x] 当前 latest 轮换更新 metadata，历史轮换不更新；
- [x] 同分钟生成的文件名不会覆盖；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（407/407）。
