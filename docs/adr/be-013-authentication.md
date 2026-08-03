# ADR-BE-013：短期 JWT + 不透明 Refresh

* 状态：Accepted
* 日期：2026-08-03

## 决策

Access：Ed25519 JWT 10–15 分钟，含 sub/session_id/device_id/token_version。Refresh：256-bit 随机，仅存 hash；轮换+重放检测撤整个 Device Session。密码 Argon2id 经 spawn_blocking。账本权限每 Command 校验。
