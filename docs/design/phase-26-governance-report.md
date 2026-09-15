# Phase 26 — 备份治理报告导出

## 1. 背景与动机

Phase 6–25 已提供完整备份治理闭环，但诊断信息分散在健康卡、目录和恢复历史。
用户向支持人员反馈问题时，只能截图多个页面，且容易遗漏关键状态。

本阶段增加只读、隐私安全的治理报告，将关键指标导出为 JSON 或 CSV。

## 2. 目标 / 非目标

### 目标

- **G1**：生成带 schemaVersion 和 generatedAt 的稳定报告；
- **G2**：汇总健康状态、备份策略、catalog 统计和恢复审计统计；
- **G3**：支持完整 JSON 报告；
- **G4**：支持适合表格查看的 CSV 摘要；
- **G5**：报告不包含账本内容、附件、密码、完整路径、backupId 或错误摘要；
- **G6**：使用 Phase 25 原子写入器保存报告；
- **G7**：数据治理页支持选择 JSON / CSV 并调用系统分享；
- **G8**：导出失败不改变备份、catalog 或审计状态。

### 非目标

- 不导出真实备份文件；
- 不上传报告；
- 不包含附件；
- 不做远程遥测；
- 不提供报告导入；
- 不替代恢复演练或完整性检查；
- 不保证报告内容在所有未来版本保持字节级一致，只保证 schemaVersion。

## 3. 报告结构

```json
{
  "kind": "ledgerly-governance-report",
  "schemaVersion": 1,
  "generatedAt": "...",
  "health": {
    "level": "healthy",
    "catalogCount": 3,
    "nextDueAt": "...",
    "issues": []
  },
  "backup": {
    "hasBackup": true,
    "encrypted": false,
    "incremental": true,
    "attachmentCount": 2,
    "attachmentSizeBytes": 12345,
    "hasIncrementalBase": true
  },
  "schedule": {
    "enabled": true,
    "intervalDays": 7,
    "encrypted": false
  },
  "catalog": {
    "count": 3,
    "totalSizeBytes": 45678,
    "full": 1,
    "incremental": 2,
    "encrypted": 0
  },
  "restoreAudit": {
    "count": 2,
    "successCount": 1,
    "failureCount": 1,
    "lastStatus": "success",
    "lastMode": "merge"
  }
}
```

CSV 使用 `metric,value` 两列，覆盖同样的关键摘要。

## 4. 隐私边界

明确不导出：

- `lastBackupPath` / `baseBackupPath`；
- catalog artifact path；
- safetyPath；
- backupId / baseBackupId；
- restore errorSummary；
- 账本、账户、交易、预算、规则或附件内容；
- 加密密码。

## 5. 文件端口

```dart
Future<String> writeGovernanceReport(
  String contents, {
  required String extension,
});
```

平台实现：

```text
ledgerly-governance-YYYY-MM-DD_HHmm-<microseconds>.<json|csv>
```

使用 `AtomicFileWriter` 写入，避免报告文件截断。

## 6. UI

健康卡右上角增加报告导出菜单：

```text
JSON 完整报告
CSV 摘要
```

选择格式后：

1. 生成报告；
2. 原子写入本地文件；
3. 调起系统分享；
4. 显示导出路径。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_governance_report.dart` | 报告模型、JSON/CSV、聚合服务 |
| 2 | `backup_service.dart` / `backup_file_port.dart` | 报告原子写入端口 |
| 3 | `providers.dart` | report service provider |
| 4 | `data_governance_page.dart` | 导出菜单和分享 |
| 5 | l10n ARB | 导出与错误文案 |
| 6 | `backup_governance_report_test.dart` | 字段和隐私边界 |
| 7 | `backup_file_port_test.dart` | 原子报告写入 |
| 8 | `data_governance_page_test.dart` | 页面导出 |
| 9 | 文档索引和路线图 | Phase 26 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 报告泄露路径/错误内容 | DTO 只包含白名单字段 |
| CSV 注入/逗号破坏 | 统一 CSV cell 转义 |
| 报告写入截断 | 复用 AtomicFileWriter |
| 分享取消被误判失败 | 分享只是调用系统入口，不要求返回值 |
| 未来 schema 变化 | 固定 kind + schemaVersion |
| 报告生成影响备份状态 | 全流程只读，不修改 metadata/catalog/audit |

## 9. 验收

- [x] JSON 报告包含 schema、健康、策略、catalog、审计摘要；
- [x] CSV 摘要包含对应核心指标；
- [x] 报告不包含完整路径、backupId、密码或错误摘要；
- [x] 平台通过原子写入器保存报告；
- [x] 页面可选择 JSON / CSV 并分享；
- [x] 报告生成失败不改变任何备份状态；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（428/428）。
