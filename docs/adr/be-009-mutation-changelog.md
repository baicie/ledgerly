# ADR-BE-009：Mutation + Change Log

* 状态：Accepted
* 日期：2026-08-03

## 决策

核心表：sync_mutations、sync_changes、sync_cursors、sync_conflicts、device_sessions。Push Batch 非一大事务；每 Mutation 独立事务按序处理。永久拒绝不阻止后续；暂时错误停止剩余。幂等返回原 Receipt。

分类沿用账户实体模型，不另建分类表。客户端本地先写入 `accounts` 和待同步
Mutation；分类创建或改名成功后，记账流程继续使用同一个账户 ID，因此历史
交易不会因名称变化失效。服务端对 `entityType=account` 生成版本化 Change Log，
客户端 Pull/Bootstrap 时重写本地账本前缀。
