# Phase 8 — 选择性备份 (Selective Backup by Book)

## 1. 背景与动机

Phase 6 落地了"全应用快照"备份，所有账本被打包到一个 `.ledgerly.json` 文件。但 Ledgerly 现在已经支持**多账本**（`LedgerRepository.listBooks()`、`MultiBookSwitcher`），用户实际场景里会出现：

| 已有 | 缺失 |
|---|---|
| 全量备份（一把梭） | 按账本子集备份（只备份"个人"，不备份"家庭"） |
| 全量恢复 | 恢复时不区分账本 |
| 单账本模式（默认账本） | 共享备份文件时需要屏蔽某些账本 |

真实场景：
- **家庭账本 + 个人账本** 用户：只想把个人账本发给自己的小号同步，家庭账本不想外泄；
- **演示账本**（用户在 app 里建了个 `demo` 账本做测试）：不希望被一起打包；
- **共享设备**：临时打开一个 `tmp` 账本用完即弃，备份时跳过。

CSV 导入/导出天然就是按账本粒度的，但 Phase 6 的全量备份把它们甩开了。本阶段把备份粒度对齐到账本。

## 2. 目标 / 非目标

### 目标
- **G1**：`BackupService.export()` / `exportToFile()` 新增可选 `bookIds` 参数；为空集合时导出所有账本（保持 Phase 6 默认行为）；
- **G2**：`DataGovernancePage` 在导出按钮上方加"选择账本"多选 chip，未选时导出全部；用户切换选择后预览区即时显示"将导出 N 个账本"；
- **G3**：备份文件 envelope 增加 `bookIds` 字段（冗余但方便 restore 端判断），schema 版本号保持 `1`（向后兼容，老备份照常可读）；
- **G4**：所有 widget 测试 + 服务测试覆盖：默认全量 / 单账本 / 多账本子集 / 空集合视作全量。

### 非目标
- 不做跨账本"合并"模式（merge 模式留给 Phase 9）；
- 不做加密备份（独立阶段）；
- 不做增量备份（diff 算法留给 Phase 9+）；
- 不动恢复逻辑（restore 仍然整文件 replace，不区分账本）；
- 不在备份文件里隐藏账本（用户可以用文本编辑器看到所有 `bookIds`）。

## 3. 设计

### 3.1 服务层

`BackupService.export({Set<String>? bookIds})`：

```dart
Future<BackupDocument> export({Set<String>? bookIds}) async {
  bookIds ??= const <String>{};  // null 或空 = 全部
  final books = await _db.select(_db.books).get();
  final filteredBooks = bookIds.isEmpty
      ? books
      : books.where((b) => bookIds.contains(b.id)).toList();
  final bookIdSet = filteredBooks.map((b) => b.id).toSet();

  final accounts = bookIdSet.isEmpty
      ? <Account>[]
      : (await _db.select(_db.accounts).get())
          .where((a) => bookIdSet.contains(a.bookId))
          .toList();
  final accountIdSet = accounts.map((a) => a.id).toSet();

  final transactions = bookIdSet.isEmpty
      ? <Transaction>[]
      : (await _db.select(_db.transactions).get())
          .where((t) => bookIdSet.contains(t.bookId))
          .toList();
  final txIdSet = transactions.map((t) => t.id).toSet();

  final entries = accountIdSet.isEmpty
      ? <TransactionEntry>[]
      : (await _db.select(_db.transactionEntries).get())
          .where((e) => txIdSet.contains(e.transactionId))
          .toList();
  final recurring = bookIdSet.isEmpty
      ? <LocalRecurringRule>[]
      : (await _recurring.listAll())
          .where((r) => bookIdSet.contains(r.bookId))
          .toList();
  final budgets = bookIdSet.isEmpty
      ? <LocalBudgetRecord>[]
      : (await _budgets.listAll())
          .where((b) => bookIdSet.contains(b.bookId))
          .toList();
  final attachments = bookIdSet.isEmpty
      ? <LocalAttachmentRecord>[]
      : (await _attachments.listAll())
          .where((a) => bookIdSet.contains(a.bookId))
          .toList();

  // Build payload + summary as before, but scoped.
  ...
}
```

`exportToFile({Set<String>? bookIds})` 把 `bookIds` 透传给 `export()`。

### 3.2 Envelope 加 `bookIds`

```json
{
  "kind": "ledgerly-backup",
  "schemaVersion": 1,
  "exportedAt": "2026-09-13T10:00:00.000Z",
  "deviceId": "<deviceId>",
  "bookIds": ["personal", "family"],        // ← 新增（冗余但方便阅读）
  "summary": { ... },
  "data": { ... }
}
```

- **schemaVersion 保持 1**：Phase 6 备份文件照样能读；
- `bookIds` 缺失时（老备份）视作"全部账本"，restore 行为不变；
- `bookIds` 数组可以为空（理论上不应该，但容错）→ 视作"全部"。

### 3.3 UI 改动

`DataGovernancePage` 在备份 section 的"导出"按钮上方加一个 `_BookSelector`：

```
┌─────────────────────────────────────────┐
│  选择账本                                │
│  [✓ 个人] [✓ 家庭] [   演示 ]            │
│  （不选 = 全部）                          │
└─────────────────────────────────────────┘

[导出全量快照]   ← 文案随选择动态变：
                  未选 → "导出全部账本 (3)"
                  选了 2 个 → "导出 2 个账本"
```

交互：
- 点击 chip 切换选中态（多选）；
- 状态保存在 `_State.selectedBookIds`（`Set<String>`）；
- Provider 提供可用账本列表（`ledgerRepositoryProvider` → `listBooks`）；
- 导出按钮 onPressed 调用 `_exportBackup(selectedBookIds: _selectedBookIds)`。

### 3.4 国际化

新增 4 个键（zh / en 各 1）：

| 键 | zh | en |
|---|---|---|
| `dataGovernanceSelectBooks` | 选择账本 | Select books |
| `dataGovernanceSelectBooksHint` | 不选 = 导出全部 | Leave empty to export all |
| `dataGovernanceExportAll` | 导出全部账本（{n}） | Export all books ({n}) |
| `dataGovernanceExportSelected` | 导出 {n} 个账本 | Export {n} books |

## 4. 实现清单

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `docs/design/phase-8-selective-backup.md` | 新增 | 本文档 |
| 2 | `apps/client/lib/application/backup_service.dart` | 修改 | export / exportToFile 接受 `bookIds` |
| 3 | `apps/client/lib/presentation/providers.dart` | 修改 | 暴露 `availableBooksProvider` |
| 4 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 修改 | `_BookSelector` + 状态传递 |
| 5 | `apps/client/lib/l10n/app_en.arb` | 修改 | +4 键 |
| 6 | `apps/client/lib/l10n/app_zh.arb` | 修改 | +4 键 |
| 7 | `apps/client/test/widget/data_governance_page_test.dart` | 修改 | +2 case |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 误操作只导出账本 A，恢复时 replace 把账本 B 数据搞丢 | UI 顶部明确显示"将覆盖当前账本 [B, C]"，文案强调 |
| `bookIds` 过滤后附件元数据引用了不存在账户 | 附件本身只引用 bookId 和 transactionId，不引用账户；已经按 bookId 过滤 |
| 旧版备份（无 bookIds 字段）恢复 | `BackupDocument.fromEnvelope` 容忍缺失字段，回退为"全量" |
| Restore 端忽略 `bookIds` 直接 replace | 当前实现就是 replace，所以语义不变；Phase 9 merge 时再使用 `bookIds` |

## 6. 验收

- [ ] `flutter analyze` 无新增 warning/error；
- [ ] `flutter test test/widget/data_governance_page_test.dart` 全部通过（含 2 个新 case）；
- [ ] `flutter test` 全量通过；
- [ ] 手动跑通：
  - 未选任何账本 → 导出文件包含所有账本；
  - 勾选"个人" → 导出文件 `data.books` 只有"个人"，`data.transactions` 也只有"个人"的；
  - 旧版备份文件（手改掉 `bookIds` 字段）→ 仍能正常 restore。