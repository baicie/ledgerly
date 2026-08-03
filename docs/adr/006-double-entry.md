# ADR-006：底层采用复式记账模型

* 状态：Accepted
* 日期：2026-08-03

## 决策

Transaction + ≥2 Entry；同币种 `SUM(amount_minor) == 0`。禁止 float。Money 使用 BigInt minor units。余额是聚合投影。转账必须同一 transaction_id。
