# 剩余阶段设计：隔离 / Jobs / 多端 / 商业化骨架

* 分支：`mvp/phase-remaining`
* 日期：2026-08-03
* 状态：**已实现并验收（测试绿）**

## A. Delete + 多账本账户隔离

- 账本 ID：登录后服务端为用户创建独立 `book_id`（UUIDv7）。
- 账户 ID：`{bookId}:{key}`，例如 `019f…:acc_cash`。
- Push 支持 `operation=delete`：软删除 + sync_changes tombstone。
- 客户端本地账本仍为 `book_default`；`sync_states.remoteBookId` 保存远端 UUID；Push/Pull 时改写账户 ID 前缀。

## B. BE-5 Job Worker

- 表 `jobs` + `FOR UPDATE SKIP LOCKED`
- `ledger-server worker|all` 领取执行
- 首批类型：`purge_expired_sessions`、`enqueue_recurring_scan`、`compact_sync_log`（可空跑）

## C. Phase 4 Web/桌面

- 启用 web/windows/macos/linux
- 宽屏 NavigationRail；`Cmd/Ctrl+N` 快速记账

## D. Phase 5 骨架

- 邀请成员 API + 设置页入口
- budgets 表 + 预算页
- attachments 元数据 + 签名上传会话占位
- recurring_rules + worker 扫描挂钩

## 验收

- `cargo test --workspace`（含 `postgres_flow`）
- `flutter test`（含 live sync）
- `dart test`（ledger_domain / ledger_sync）
