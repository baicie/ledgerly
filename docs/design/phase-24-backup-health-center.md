# Phase 24 — 备份策略健康中心

## 1. 背景与动机

Phase 6–23 已分别提供备份、完整性、自动调度、加密、目录管理和恢复审计，
但用户需要在多个区域自行组合判断：

- 最近备份是否过期；
- 自动备份是否启用；
- 加密自动备份密码是否仍可用；
- 目录文件是否缺失或损坏；
- 最近备份是否缺少 base；
- 最近恢复是否失败。

本阶段增加一个只读聚合检查服务，把分散状态汇总为可解释的健康等级和建议动作。

## 2. 目标 / 非目标

### 目标

- **G1**：输出 healthy / warning / critical 三级健康状态；
- **G2**：聚合最近备份时间、cadence、自动加密密码和恢复审计；
- **G3**：复用完整性检查发现 missing / corrupted 文件；
- **G4**：检查 latest 和增量 base 是否仍在 catalog；
- **G5**：每个问题使用稳定 issue code，UI 负责本地化；
- **G6**：返回一个推荐操作；
- **G7**：数据治理页展示等级、原因、catalog 数量和下次计划；
- **G8**：支持手动刷新，并在备份/设置/校验后自动刷新。

### 非目标

- 不自动修复缺失或损坏文件；
- 不自动生成备份；
- 不绕过用户确认修改自动备份设置；
- 不解析或上传备份内容；
- 不替代恢复演练；
- 不改变现有备份/恢复行为。

## 3. 数据模型

```dart
enum BackupHealthLevel { healthy, warning, critical }

enum BackupHealthIssueCode {
  noBackup,
  staleBackup,
  autoBackupDisabled,
  encryptedPasswordMissing,
  secureStorageUnavailable,
  verificationFailed,
  filesMissing,
  filesCorrupted,
  latestBackupNotCataloged,
  latestIncremental,
  incrementalBaseMissing,
  recentRestoreFailed,
}

enum BackupHealthAction {
  createBackup,
  enableAutoBackup,
  configureAutoPassword,
  inspectFiles,
  none,
}
```

健康快照包含 metadata、schedule、catalog 数量、问题列表和 nextDueAt。

## 4. 检查规则

| 条件 | 等级 | 建议 |
|---|---|---|
| 从未备份 | critical | 立即备份 |
| 超过 cadence / 14 天 | warning | 立即备份 |
| 自动备份未启用 | warning | 启用自动备份 |
| 最近为增量文件 | warning | 生成便携全量 |
| latest/base 不在 catalog | warning | 检查目录 |
| 加密自动备份密码缺失 | critical | 设置密码 |
| 安全存储不可用 | critical | 设置密码 |
| 完整性检查失败 | critical | 检查文件 |
| missing / corrupted 文件 | critical | 检查文件 |
| 最近恢复失败 | warning | 查看恢复历史 |

优先级按照风险和处理顺序选择推荐动作。

## 5. UI

数据治理页在“上次备份”卡下方增加健康卡：

- 等级图标与 healthy / warning / critical；
- 问题原因列表；
- catalog 数量和下次计划日期；
- 推荐操作按钮；
- 重新检查按钮。

操作复用现有：

- 立即备份；
- 启用自动备份；
- 设置自动加密备份密码；
- 完整性检查。

## 6. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_health.dart` | 聚合模型和检查服务 |
| 2 | `providers.dart` | health service/provider |
| 3 | `data_governance_page.dart` | 健康卡和推荐动作 |
| 4 | l10n ARB | 等级、问题、动作与摘要 |
| 5 | `backup_health_test.dart` | 健康、过期、密码、missing |
| 6 | `data_governance_page_test.dart` | 健康卡展示与操作 |
| 7 | 文档索引和路线图 | Phase 24 |

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 页面加载时哈希大文件变慢 | 在数据治理页一次性检查，并显示 loading 状态 |
| 健康规则与 UI 文案耦合 | 应用层只返回 issue enum |
| 多个问题导致操作不明确 | 按严重度和处理顺序返回一个推荐动作 |
| 自动备份可选但被误报错误 | 未启用使用 warning，而非 critical |
| 恢复历史较早失败长期告警 | 以最近一条恢复结果为准 |
| 完整性检查本身写入 catalog | 仅补 hash/base 元数据，不删除文件 |

## 8. 验收

- [x] 无备份为 critical 并建议立即备份；
- [x] 完整策略可报告 healthy；
- [x] 过期备份按 cadence 报告 warning；
- [x] 加密自动备份缺密码报告 critical；
- [x] missing/corrupted catalog 文件报告 critical；
- [x] UI 展示等级、原因、摘要和推荐动作；
- [x] 刷新和操作后健康状态更新；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（421/421）。
