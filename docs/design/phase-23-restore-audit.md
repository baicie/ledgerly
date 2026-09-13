# Phase 23 — 备份恢复审计与安全备份历史

## 1. 背景与动机

恢复操作会自动写入恢复前安全备份，但当前 UI 只提示安全文件路径，用户重启后
无法看到：

- 最近恢复是否成功；
- 使用了 replace 还是 merge；
- 恢复来源的 backupId；
- 对应安全备份在哪里；
- 失败恢复是否也留下了可回滚文件。

本阶段增加恢复审计历史，并把安全备份的保留和删除与审计记录关联。

## 2. 目标 / 非目标

### 目标

- **G1**：记录 replace / merge 的成功和失败恢复；
- **G2**：记录时间、来源 backupId、安全备份路径和 merge 统计；
- **G3**：失败记录只保存截断后的错误摘要；
- **G4**：历史最多保留 50 条；
- **G5**：数据治理页展示恢复历史；
- **G6**：历史项可分享关联安全备份；
- **G7**：删除历史项时同步删除关联安全备份；
- **G8**：cleanup 保留最近恢复审计关联的安全备份；
- **G9**：审计写入失败不影响恢复结果。

### 非目标

- 不保存账本 payload、附件或密码；
- 不自动恢复或删除安全备份；
- 不记录每次同步或自动备份；
- 不提供跨设备审计同步；
- 不通过审计条目执行真实恢复；
- 不修改备份文件 schema。

## 3. 数据模型

```dart
enum BackupRestoreAuditStatus { success, failed }
enum BackupRestoreAuditMode { replace, merge }

class BackupRestoreAudit {
  final String id;
  final DateTime at;
  final BackupRestoreAuditMode mode;
  final BackupRestoreAuditStatus status;
  final String? backupId;
  final String? safetyPath;
  final String? errorSummary;
  final int addedBooks;
  final int replacedBooks;
  final int skippedBooks;
}
```

存储接口：

```dart
class BackupRestoreAuditStore {
  Future<List<BackupRestoreAudit>> read();
  Future<void> record({...});
  Future<void> remove(String id);
  Future<void> clear();
}
```

## 4. 恢复流程

```text
write safety backup
  -> replace / merge
  -> success? record(success, merge counts)
  -> failed?  record(failed, truncated error)
  -> refresh restore history
```

审计写入位于恢复结果之后，并使用独立 try/catch。即使 SharedPreferences
不可写，恢复本身仍按原结果完成。

## 5. 保留和删除

- `cleanupBackups()` 将最近一条带 safetyPath 的审计加入保护路径；
- catalog 单项删除不能删除任何审计关联的安全备份；
- 删除恢复历史时：
  - 有 safetyPath：删除文件、catalog 记录和审计；
  - 无 safetyPath：只删除审计；
  - 安全文件属于当前 base/latest 时拒绝删除。

## 6. UI

备份区域新增“恢复历史 · N 次”：

- replace / merge；
- 成功 / 失败；
- 恢复时间；
- 来源 backupId；
- 关联安全备份路径；
- 失败错误摘要；
- 分享安全备份；
- 删除记录和安全备份。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_restore_audit.dart` | 审计模型与持久化 |
| 2 | `backup_service.dart` | cleanup 保护、历史删除 |
| 3 | `providers.dart` | 审计 store/provider |
| 4 | `data_governance_page.dart` | 恢复记录、历史列表与操作 |
| 5 | l10n ARB | 审计状态与操作文案 |
| 6 | `backup_restore_audit_test.dart` | 上限、保留、删除 |
| 7 | `data_governance_page_test.dart` | 成功/失败恢复审计 |
| 8 | 文档索引和路线图 | Phase 23 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 审计失败影响恢复结果 | 独立 try/catch，审计为辅助数据 |
| 历史无限增长 | 最多保留 50 条 |
| 删除历史导致安全文件孤立 | 删除时同步处理文件与 catalog |
| cleanup 删除审计安全备份 | 最近审计 safetyPath 强制保护 |
| 错误信息包含敏感内容 | 只保存压缩、截断后的错误摘要 |
| 历史记录指向 missing 文件 | UI 允许删除记录，分享操作仅在存在路径时启用 |

## 9. 验收

- [x] replace 成功写入审计；
- [x] merge 成功记录统计；
- [x] 失败恢复记录错误摘要和安全备份；
- [x] 审计最多保留 50 条；
- [x] cleanup 保护最近审计关联安全备份；
- [x] 删除历史同步删除关联安全备份；
- [x] UI 展示、分享和删除恢复历史；
- [x] 审计失败不影响恢复；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（415/415）。
