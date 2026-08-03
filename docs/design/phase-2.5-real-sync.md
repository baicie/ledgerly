# Phase 2.5 设计：真实同步闭环

* 状态：In progress
* 分支：`mvp/phase-2.5-real-sync`
* ADR：007、BE-007/009/011/012/013

## 目标

把 MVP 从「内存演示」推进到可联调的真实闭环：

1. 服务端可选 PostgreSQL 持久化（`DATABASE_URL` 存在时启用）。
2. 客户端本地 `pending_mutations` + `sync_state`。
3. HTTP Push/Pull/Bootstrap 对接服务端。
4. 同步中心展示真实 pending/cursor/错误码。
5. 冲突写入本地并在冲突页展示。

## 架构

```text
Flutter UI
  → LedgerAppService (本地事务 + enqueue mutation)
  → Drift (transactions / pending_mutations / sync_state / conflicts)
  → SyncService (Dio)
       → POST /sync/push
       → GET  /sync/pull
       → POST /sync/bootstrap
  → ledger-server (MemoryStore | PgStore)
```

## 服务端

- `AppState.pool: Option<PgPool>`
- 无 `DATABASE_URL`：保持现有 MemoryStore（单测不依赖 Docker）
- 有 `DATABASE_URL`：读写走 PostgreSQL；`/health/ready` 探测 DB
- migrate 执行 `001_init.sql`

## 客户端 Schema 增量

- `pending_mutations`
- `sync_state`（bookId, cursor, deviceId）
- `sync_conflicts`
- `transactions.deletedAt`（Tombstone 预留，打磨阶段启用）

## 验收

- [x] `cargo test` 内存模式仍绿
- [x] 有 PG 时 migrate + ready 成功；push/pull 持久化后重启仍在
- [x] 客户端创建支出产生 pending；sync 后 pending 清空且 cursor 前进
- [x] 重复 push 同 mutationId 幂等
- [x] 冲突写入 conflicts 表并可在 UI 解决
