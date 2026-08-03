# Phase 1 设计：单机离线 MVP

* 状态：Ready for implementation
* 分支：`mvp/phase-1-offline`
* ADR：ADR-002–005、ADR-006

## 目标

Flutter 应用以本地 Drift/SQLite 为唯一数据源，支持离线收入/支出/转账与流水查询；余额由分录重算。

## 架构

```text
UI (Riverpod ViewModel)
  → Application Service (CreateExpense/Income/Transfer)
    → ledger_domain factories
    → Drift repositories (local transaction)
```

## Schema（本地）

- books
- accounts
- categories（首期可与 expense/income 账户合并使用，保留表）
- transactions
- transaction_entries
- local_settings

首期不同步：无 pending_mutations（Phase 2 加入）。

## 种子数据

创建默认账本 + 现金/银行卡资产账户 + 餐饮/交通支出 + 工资收入。

## 验收

- [x] 冷启动从本地库加载账户与流水
- [x] 离线创建支出后列表立即更新
- [x] 账户余额 = 分录聚合
- [x] `flutter test` 覆盖创建与余额重算
