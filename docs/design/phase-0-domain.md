# Phase 0 设计：领域模型验证

* 状态：Ready for implementation
* 分支：`mvp/phase-0-domain`
* ADR：ADR-006

## 目标

交付可独立测试的纯 Dart 包 `packages/ledger_domain`，验证复式记账不变量，不依赖 Flutter/Drift/网络。

## 范围

### In

- `Money`（BigInt minor units + CurrencyCode）
- `AccountId` / `TransactionId` / `EntryId`（字符串 ID 包装）
- `Account`（类型：asset/liability/income/expense/equity）
- `Transaction` + `TransactionEntry`
- 工厂：支出、收入、转账、拆分、退款
- `validateBalanced()`：同币种分录和为 0
- 领域错误类型

### Out

- 持久化、同步、UI、多币种汇率换算（仅预留字段可选）

## 包结构

```text
packages/ledger_domain/
├── pubspec.yaml
├── lib/
│   ├── ledger_domain.dart
│   └── src/
│       ├── money.dart
│       ├── currency.dart
│       ├── ids.dart
│       ├── account.dart
│       ├── transaction.dart
│       ├── entry.dart
│       ├── errors.dart
│       └── builders.dart
└── test/
    ├── money_test.dart
    ├── balance_test.dart
    ├── transfer_test.dart
    └── split_refund_test.dart
```

## 验收

- [x] `dart test` 在 `packages/ledger_domain` 全绿
- [x] 不平衡交易构造失败
- [x] 转账两条分录同 transactionId 且和为 0
- [x] 拆分/退款覆盖
- [x] 金额边界（零、负号方向、极大值）有测试
