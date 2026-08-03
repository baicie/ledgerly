# ADR-016：测试策略

* 状态：Accepted
* 日期：2026-08-03

## 决策

Domain：复式/转账/退款/边界。Repository：真实 SQLite。同步：双设备幂等/冲突/Cursor 过期/Bootstrap。UI：记账主路径与冲突。E2E：双客户端 + Rust API + PostgreSQL。
