# ADR-007：领域限定 Push/Pull 同步协议

* 状态：Accepted
* 日期：2026-08-03

## 决策

核心接口：`POST sync/push`、`GET sync/pull`、`POST/GET bootstrap`。WebSocket 仅 `sync.available` 唤醒。

Mutation 幂等键：`(book_id, device_id, mutation_id)`。业务数据 + Change Log + Receipt 同事务。游标为服务端单调序列。Commit 不可拆页。删除用 Tombstone。
