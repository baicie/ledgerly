# ADR-BE-015：WebSocket 只负责同步唤醒

* 状态：Accepted
* 日期：2026-08-03

## 决策

消息 `sync.available`；权威数据必须 Pull。单实例进程内 Broadcast；多实例优先 PG LISTEN/NOTIFY。
