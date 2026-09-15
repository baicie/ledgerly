# Phase 15 — 备份目录与保留策略

## 1. 背景与动机

Phase 12 会按计划自动创建快照，Phase 14 又增加了增量文件和基础全量文件。
当前元数据只记录“最后一次”和“当前基础”，用户无法看到本机到底有多少备份，
也没有清理入口。长期使用后，应用文档目录会持续遗留旧自动备份。

真实风险：

- 自动增量/全量文件无限增长；
- 用户误删基础文件后，后续增量无法恢复；
- 用户不知道哪些文件可以安全清理；
- 手工导出的重要备份不应被自动清理策略删除。

本阶段增加本机备份目录和保守的保留策略。

## 2. 目标 / 非目标

### 目标

- **G1**：记录每次成功导出的备份元数据：ID、路径、时间、类型、来源、文件大小；
- **G2**：来源区分手工、自动、恢复前安全备份；
- **G3**：手工备份永久保留，不参与自动清理；
- **G4**：当前基础全量、最近一次备份始终受保护；
- **G5**：自动备份和恢复前安全备份分别保留最新 N 份，默认各 3 / 1 份；
- **G6**：数据治理页显示本机备份数量与总占用，并提供清理入口；
- **G7**：清理先确认，结果展示删除数量与释放空间；
- **G8**：文件已不存在时视为已清理，不阻塞其他文件删除。

### 非目标

- 不自动上传或删除云盘文件；
- 不清理用户通过分享/文件管理器另存的文件；
- 不删除手工导出的明文或加密备份；
- 不做按时间窗口保留；
- 不做备份目录的全文搜索或逐条删除 UI。

## 3. 数据模型

### 3.1 BackupArtifact

```dart
enum BackupArtifactKind { full, incremental, encrypted }
enum BackupArtifactSource { manual, automatic, safety }

class BackupArtifact {
  final String backupId;
  final String path;
  final DateTime createdAt;
  final BackupArtifactKind kind;
  final BackupArtifactSource source;
  final int sizeBytes;
}
```

`BackupCatalogStore` 使用 SharedPreferences 保存 JSON 数组，按 backupId upsert。
为避免偏好项无限增长，仅保留最近 100 条目录记录；删除文件时同步移除记录。

### 3.2 记录时机

| 操作 | source |
|---|---|
| 数据治理页手工导出 | `manual` |
| 自动备份 | `automatic` |
| restore 前安全备份 | `safety` |

目录写入是辅助元数据，失败不能把已经成功写出的备份标记为失败。

## 4. 保留策略

`BackupService.cleanupBackups()` 执行以下规则：

1. 读取目录和当前备份元数据；
2. 永久保护：
   - 所有 `manual`；
   - `metadata.lastBackupPath`；
   - `metadata.baseBackupPath`；
3. 自动备份按时间倒序保留最新 3 份；
4. 安全备份按时间倒序保留最新 1 份；
5. 其余 artifact 调用 `BackupFilePort.deleteBackup`；
6. 删除成功或文件不存在时移除目录记录；
7. 单个删除失败不阻止其他文件，最终返回失败数量。

```dart
class BackupCleanupResult {
  final int deletedCount;
  final int freedBytes;
  final int failedCount;
}
```

重点：**基础全量即使已经很旧也不会被删除**，否则最新增量无法恢复。

## 5. File Port

`BackupFilePort` 增加：

```dart
Future<int> fileSize(String source);
Future<void> deleteBackup(String source);
```

- 文件不存在时 `fileSize == 0`、`deleteBackup` 正常返回；
- `InMemoryBackupFilePort` 同时移除 `rawFiles` 与 `envelopes`；
- 插件端口删除应用文档目录中的备份文件。

## 6. UI

数据治理页备份区块新增备份目录卡：

```text
本机备份 5 份 · 42.3 MB
[清理旧备份]
```

清理确认对话框说明：

- 手工备份不会删除；
- 当前基础备份和最近备份不会删除；
- 自动备份仅保留最新 3 份。

完成后提示：

```text
已清理 4 份备份，释放 18.6 MB。
```

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `apps/client/lib/application/backup_catalog_store.dart` | artifact / store |
| 2 | `apps/client/lib/application/backup_service.dart` | 记录 catalog、cleanup API |
| 3 | `apps/client/lib/application/auto_backup.dart` | 标记 automatic 来源 |
| 4 | `apps/client/lib/platform/backup_file_port.dart` | fileSize / deleteBackup |
| 5 | `apps/client/lib/presentation/providers.dart` | catalog provider |
| 6 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 目录状态、确认、清理结果 |
| 7 | l10n ARB | 新文案 |
| 8 | `apps/client/test/application/backup_catalog_test.dart` | 保留规则和删除测试 |
| 9 | `apps/client/test/widget/data_governance_page_test.dart` | 清理入口测试 |
| 10 | 文档索引和路线图 | Phase 15 状态 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 删除增量依赖的基础文件 | 基础路径强制保护 |
| 自动清理重要手工备份 | manual 永不参与清理 |
| 目录记录与实际文件不同步 | 缺失文件按已删除处理；失败项保留记录 |
| SharedPreferences JSON 损坏 | 回到空目录，不影响备份和恢复 |
| 删除目录外的恶意路径 | 仅删除 catalog 中由本应用写入的路径，仍不跟随用户外部路径 |

## 9. 验收

- [x] 每次手工/自动导出与安全备份都进入 catalog；
- [x] 手工备份不参与清理；
- [x] 当前 base 与 last 路径不被删除；
- [x] 自动备份保留最新 3 份，安全备份保留最新 1 份；
- [x] 删除后文件与 catalog 同步；
- [x] 数据治理页显示数量、大小并完成清理确认与结果提示；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（383/383）。
