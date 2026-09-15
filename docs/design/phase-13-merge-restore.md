# Phase 13 — 跨账本 merge 恢复

## 1. 背景与动机

Phase 6–12 的恢复是 **replace**：备份必须先清空本机账本，再整体写回。
这适合“迁移到新设备”或“完整回滚”，但不适合下面的常见场景：

- 用户在新设备上已经记了几天账，随后导入旧设备备份；
- 家庭成员发来一个账本备份，希望追加到当前设备；
- 用户误删单个账本后，希望只把该账本补回来，而不覆盖其他数据。

本阶段新增 merge 模式：保留当前设备已有账本，只把备份中尚不存在、
或仍处于空占位状态的账本合并进来。

## 2. 目标 / 非目标

### 目标

- **G1**：恢复预览可选择“替换本机数据”或“合并新账本”，默认仍为 replace；
- **G2**：merge 以账本为冲突边界，不自动合并同一个账本内部的不同交易版本；
- **G3**：备份账本 ID 在当前设备不存在时，完整导入该书及其账户、交易、分录、
  周期规则、预算、附件和附件二进制；
- **G4**：备份账本 ID 已存在，但本机该书仍是无交易、无周期、无预算、无附件，
  且账户全部为默认账户时，视为空占位账本并替换；
- **G5**：备份账本 ID 已存在且本机已有真实业务数据时，整本跳过，不覆盖、
  不尝试行级合并；
- **G6**：全局商户规则按 `id` 合并；本机同 ID 规则优先，备份只补充缺口；
- **G7**：merge 不恢复 `pendingMutations`、`syncConflicts` 或原设备同步游标；
  新导入/替换的账本使用当前设备 ID 建立空白同步状态；
- **G8**：merge 在单个数据库事务中完成；任一主键冲突或写入失败时整体回滚；
- **G9**：返回合并摘要，UI 明确显示新增、替换、跳过的账本数量。

### 非目标

- 不做同一个账本内的逐交易 merge；
- 不做冲突选择器或字段级合并；
- 不重新映射账本/账户/交易 ID；
- 不把两个远程 book 自动合并成一个远端账本；
- 不改变备份文件格式，`schemaVersion` 仍为 2 / 外层加密容器仍为 3。

## 3. 合并语义

### 3.1 账本判定

对备份中的每个 book：

| 本机状态 | merge 行为 |
|---|---|
| 相同 ID 不存在 | 新增整本 |
| 相同 ID 存在，但仅有默认账户且业务表为空 | 删除空占位后导入备份整本 |
| 相同 ID 存在且已有业务数据 | 跳过整本 |

“已有业务数据”包括本机该账本下任一交易（含软删除记录）、周期规则、
预算或附件元数据；只要存在一项，就不允许备份覆盖。

### 3.2 级联范围

只处理被选中账本的记录：

```text
selectedBooks
  → accounts.book_id
  → transactions.book_id
      → transaction_entries.transaction_id
  → local_recurring_rules.book_id
  → local_budgets.book_id
  → local_attachments.book_id
      → attachment binaries by id
```

被跳过账本的所有记录和附件二进制都不写入。

### 3.3 同步状态

备份中的同步状态本来就不属于数据快照。merge 后：

- 新建账本插入 `sync_states(book_id, current_device_id, cursor=0, remote_book_id=NULL)`；
- 被替换的空占位账本先删除旧同步状态，再建立同样的空白状态；
- 被跳过账本保持其现有同步状态不变。

## 4. API 与 UI

### 4.1 `BackupService`

```dart
enum BackupRestoreMode { replace, merge }

class BackupMergeResult {
  final int addedBooks;
  final int replacedBooks;
  final int skippedBooks;
  final int addedAccounts;
  final int addedTransactions;
  final int addedRecurringRules;
  final int addedBudgets;
  final int addedAttachments;
  final int addedMerchantRules;
}

Future<BackupMergeResult> merge(
  BackupDocument document, {
  String? password,
});
```

`restore()` 的现有签名和 replace 行为保持不变。

### 4.2 恢复预览

`_RestorePreviewCard` 增加分段选择：

```text
[ 替换本机数据 ] [ 合并新账本 ]
```

选择 merge 后，确认对话框改为说明“同 ID 且有数据的账本会跳过”，
成功后显示：

```text
已合并 2 个新账本，替换 1 个空账本，跳过 1 个已有账本。
```

## 5. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `apps/client/lib/application/backup_service.dart` | 增加 merge API、结果对象和账本级事务逻辑 |
| 2 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 恢复模式选择、确认文案和结果提示 |
| 3 | `apps/client/lib/l10n/app_zh.arb` / `app_en.arb` | merge 模式文案 |
| 4 | `apps/client/test/application/backup_service_merge_test.dart` | 新增服务级 merge 测试 |
| 5 | `apps/client/test/widget/data_governance_page_test.dart` | 覆盖模式选择和合并结果 |
| 6 | `docs/design/README.md` / `docs/roadmap/phases.md` | 阶段索引与状态 |

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 同 ID 账本被错误覆盖 | 只有“默认账户 + 全业务表为空”才替换，其余整本跳过 |
| 主键碰撞导致半写入 | 数据库写入单一事务，失败整体回滚 |
| 跳过附件却写入二进制 | 只写最终选中附件 ID 的二进制 |
| 旧同步游标污染新账本 | 不恢复同步状态，为新增账本创建 cursor=0 的本地状态 |
| 用户不了解 merge 不会合并同书数据 | 预览页和确认框都明确写明“同 ID 已有账本会跳过” |

## 7. 验收

- [x] `flutter analyze` 无 issue；
- [x] 新增不同 ID 账本可完整合并，原账本不变；
- [x] 空默认账本可被同 ID 备份替换；
- [x] 同 ID 已记账或被修改的账本被跳过；
- [x] 被跳过账本的附件二进制不写入；
- [x] 商户规则按 ID 合并且本机规则优先；
- [x] widget 测试覆盖 replace / merge 切换与结果提示；
- [x] `flutter test` 全量通过（372/372）。
