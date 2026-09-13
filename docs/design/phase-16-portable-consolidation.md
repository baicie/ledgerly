# Phase 16 — 增量备份便携化

## 1. 背景与动机

Phase 14 的增量文件依赖本机基础全量文件，适合本地自动备份和回滚，
但不适合直接分享给另一台设备：

```text
base.ledgerly.zip + latest.ledgerly.inc.zip
```

用户若只分享增量文件，接收方无法恢复。Phase 15 已经能识别和保护
base/latest，本阶段增加一个显式操作：把当前基础快照和最新增量合成成
新的独立全量 `.ledgerly.zip`。

## 2. 目标 / 非目标

### 目标

- **G1**：新增 `BackupService.consolidateLatest()`；
- **G2**：只处理“最近一次备份是增量”的场景，其它情况返回 no-op；
- **G3**：读取本机 base，应用最新 delta，得到备份时点的完整快照；
- **G4**：写出新的明文全量 `.ledgerly.zip`，不依赖旧 base/delta；
- **G5**：新文件使用新 `backupId`，登记为 `manual`，受到 Phase 15 永久保护；
- **G6**：更新 metadata 的 last/base 为新全量，后续增量以它为基线；
- **G7**：数据治理页在最近备份为增量时显示“生成便携备份”，成功后分享入口恢复。

### 非目标

- 不自动上传该全量文件；
- 不删除旧 base/delta，清理仍由 Phase 15 显式执行；
- 不压缩为新的文件格式；
- 不把当前数据库尚未进入最近备份的改动混入快照；
- 不支持把加密增量（当前不存在）合成明文文件。

## 3. API

```dart
class BackupConsolidationResult {
  final String path;
  final String backupId;
  final int sizeBytes;
}

Future<BackupConsolidationResult?> consolidateLatest();
```

返回 `null` 表示最近备份不是增量，无需便携化。

### 流程

```text
metadata.lastBackupPath
  → readBackup
  → require isIncremental
  → _materializeIncremental(base + delta)
  → assign new backupId
  → write full .ledgerly.zip
  → catalog(manual)
  → metadata.record(full)
```

基础缺失或损坏时继承 Phase 14 的明确 `BackupFormatException`。

## 4. UI

最近备份为增量时，备份操作区显示：

```text
[生成便携备份]
```

成功后提示新文件路径，并刷新：

- status card 不再显示 incremental-only；
- 分享按钮可用；
- catalog 增加一条手工全量备份。

## 5. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `apps/client/lib/application/backup_service.dart` | consolidation API |
| 2 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 便携化按钮和结果 |
| 3 | l10n ARB | 新文案 |
| 4 | `apps/client/test/application/backup_consolidation_test.dart` | 独立恢复/no-op/文件记录 |
| 5 | `apps/client/test/widget/data_governance_page_test.dart` | 按钮与分享恢复 |
| 6 | 文档索引和路线图 | Phase 16 |

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 合成时误包含未备份的新数据 | 只 materialize 最近 delta，不重新读取 live DB |
| 新全量覆盖 delta ID | 生成新 backupId |
| 旧 delta 被误认为 last | metadata.record 更新 last 和 base |
| 新全量被清理 | catalog source=manual 永久保护 |

## 7. 验收

- [x] 最近为增量时生成独立全量文件；
- [x] 删除旧 base/delta 后，新文件仍可恢复；
- [x] 新 snapshot 与新全量文件状态一致；
- [x] 最近为全量时返回 no-op；
- [x] catalog 记录 manual full，metadata 更新 base/last；
- [x] 数据治理页按钮、分享状态和结果提示正确；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（386/386）。
