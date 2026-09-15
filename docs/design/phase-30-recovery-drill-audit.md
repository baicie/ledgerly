# Phase 30 — 恢复演练审计与就绪度

## 1. 背景与动机

Phase 29 证明备份可以恢复到隔离数据库，但演练结果只存在于当前页面的对话框。
应用重启后无法回答三个关键问题：

- 最近是否成功完成过恢复演练；
- 最近一次演练是否失败；
- 当前备份策略是否长期没有做过恢复验证。

本阶段持久化恢复演练结果，并把它纳入备份策略健康中心和治理报告。

## 2. 目标 / 非目标

### 目标

- **G1**：新增独立的 `BackupRecoveryDrillAuditStore`；
- **G2**：最近备份与任意 catalog artifact 的演练都自动记录；
- **G3**：成功记录加密/增量标志及账本、流水、附件数量；
- **G4**：失败记录时间与失败状态；
- **G5**：历史最多保留 20 条，按时间倒序；
- **G6**：审计损坏时返回空历史，不阻塞演练；
- **G7**：审计写入失败不影响演练结果或原始异常；
- **G8**：健康中心识别未演练、最近失败、超过 90 天未成功演练；
- **G9**：推荐操作可直接运行最近备份的恢复演练；
- **G10**：治理报告 schema v2 汇总演练成功/失败数量；
- **G11**：清空本机数据时同时清除演练审计。

### 非目标

- 不在后台自动运行恢复演练；
- 不保存备份路径、backupId、密码、附件内容或错误详情；
- 不把演练审计同步到服务端；
- 不替代 Phase 29 的隔离数据库恢复矩阵；
- 不自动修复演练发现的损坏备份。

## 3. 数据模型

```dart
enum BackupRecoveryDrillAuditStatus { success, failed }

class BackupRecoveryDrillAudit {
  final DateTime at;
  final BackupRecoveryDrillAuditStatus status;
  final bool encrypted;
  final bool incremental;
  final int bookCount;
  final int transactionCount;
  final int attachmentCount;
}
```

存储键为 `ledgerly.backup.recoveryDrillAudits`，最多保留 20 条。

## 4. 执行与记录流程

```text
runRecoveryDrill / runCatalogRecoveryDrill
  -> 读取、解密、合成并校验备份
  -> 成功:
       recordSuccess(status=success, flags, counts)
    失败:
       recordFailure(status=failed)
       rethrow 原始异常
```

审计持久化属于辅助信息。写审计失败时继续返回成功结果或原始演练异常。

## 5. 健康中心

只要存在最近备份，健康中心就评估演练状态：

| 状态 | 问题 | 推荐操作 |
|---|---|---|
| 无记录 | `recoveryDrillNeverRun` | 运行恢复演练 |
| 最近为失败 | `recoveryDrillFailed` | 运行恢复演练 |
| 最近成功超过 90 天 | `recoveryDrillStale`，值为天数 | 运行恢复演练 |
| 90 天内成功 | 无问题 | 无 |

健康卡片同时展示：

```text
Recovery drill: not run yet
Last recovery drill passed: <date>
Last recovery drill failed: <date>
```

## 6. 治理报告

治理报告升到 schema v2，新增 `recoveryDrill`：

- 总数；
- 成功数量；
- 失败数量；
- 最近时间和状态。

报告不包含备份路径、backupId、密码或演练错误详情。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_recovery_drill_audit.dart` | 审计模型、持久化、20 条上限 |
| 2 | `backup_service.dart` | 成功/失败自动记录、wipe 清理 |
| 3 | `backup_health.dart` | 未演练、失败、过期问题与操作 |
| 4 | `backup_governance_report.dart` | schema v2 演练统计 |
| 5 | `data_governance_page.dart` | 演练就绪度展示与健康操作 |
| 6 | l10n ARB | 状态和操作文案 |
| 7 | 应用与 widget 测试 | 存储、记录、健康、UI、报告 |
| 8 | 文档索引和路线图 | Phase 30 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 审计泄露敏感信息 | 只保存状态和计数，不保存路径、ID、错误 |
| 审计写入失败导致演练失败 | 审计异常被吞掉，保留演练结果 |
| 历史无限增长 | 最多 20 条并倒序截断 |
| 错误密码尝试污染就绪度 | 后续成功演练会成为最新记录并恢复正常 |
| 长期未演练仍显示健康 | 90 天阈值产生 warning |
| 清空后旧审计仍存在 | `wipeLocalData` 同步清理审计 |

## 9. 验收

- [x] 成功与失败演练自动写入审计；
- [x] 审计按时间倒序且最多保留 20 条；
- [x] 损坏审计不阻塞读取；
- [x] 健康中心识别未演练、失败和超过 90 天；
- [x] 健康操作可以运行恢复演练；
- [x] 治理报告 schema v2 不包含敏感字段；
- [x] 清空本机数据会清除演练审计；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（449/449）。
