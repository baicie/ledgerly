# ADR-011：认证、安全与隐私

* 状态：Accepted
* 日期：2026-08-03

## 决策

短期 Access Token + 可轮换 Refresh Token + 每设备 Session。Native：Refresh/DB key 进 Keychain；Access 仅内存。Web：Refresh 用 HttpOnly Secure Cookie。

V1 不做完整 E2EE。日志禁止交易正文、商户、账户名、精确金额、Token、完整 Payload。
