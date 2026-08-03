# Phase 2 设计：同步最小闭环

* 分支：`mvp/phase-2-sync`
* ADR：007、008、BE-009–012

## 目标

客户端 pending mutation 队列 + Push/Pull/Bootstrap；服务端幂等 Receipt + Change Log；双端可收敛。

## 客户端

- `pending_mutations` 表（或内存队列包 `ledger_sync`）
- Push 按序；失败重试同 mutationId
- Pull 应用完整 Commit
- Cursor 持久化；过期触发 Bootstrap

## 验收

- [x] 协议文档 `docs/sync-protocol/v1.md`
- [x] 服务端 Push 幂等 / 不平衡拒绝（api_flow）
- [x] `ledger_sync` 双设备模拟收敛测试
