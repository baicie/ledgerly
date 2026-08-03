# ADR-BE-005：HTTP 使用 Axum + Tower

* 状态：Accepted
* 日期：2026-08-03

## 决策

Handler 只做路由/解析/鉴权提取/校验/调用 Application Service/错误转换。禁止 Handler 内 SQL。

中间件顺序：RequestId → Forwarded/IP → Tracing → PanicCatch → Timeout → BodyLimit → CORS → AuthN → AuthZ → RateLimit → Handler。

体限制：JSON 1MiB；Sync Push 4MiB。超时：普通 10s；Sync 30s；Bootstrap 页 60s；health 2s。
