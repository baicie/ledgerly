# Phase 5+ / BE-6 一次性收口

* 分支：`mvp/phase-remaining`
* 日期：2026-08-03
* 状态：**已实现并验收**

## 决策

| 项 | 选择 |
|----|------|
| 对象存储 | 本地磁盘 + HMAC-SHA256 签名 PUT/GET |
| 产品深度 | 表 + API + 客户端页 + 测试 |
| JWT | Ed25519（硬切，废弃 HS256） |
| OTel | `OTEL_EXPORTER_OTLP_ENDPOINT` 有值则导出，否则 tracing-only |
| 限流 | 进程内 token-bucket（按 IP） |

## 表（003_phase5plus.sql）

- `fx_rates`、`transaction_revisions`、`subscriptions`
- `books.base_currency`

## 验收

- cargo test / clippy / flutter test
- 附件：签名上传 → complete → download
- 登录返回 plan；dev-upgrade 可升档
