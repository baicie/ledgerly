# ADR-BE-009：Mutation + Change Log

* 状态：Accepted
* 日期：2026-08-03

## 决策

核心表：sync_mutations、sync_changes、sync_cursors、sync_conflicts、device_sessions。Push Batch 非一大事务；每 Mutation 独立事务按序处理。永久拒绝不阻止后续；暂时错误停止剩余。幂等返回原 Receipt。
