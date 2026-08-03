# ADR-BE-000：记账应用后端总体架构

* 状态：Accepted
* 日期：2026-08-03
* 客户端：Flutter Local-first
* 首期部署：单机 2C4G
* 原则：正确性优先、低常驻资源、单体优先、按需拆分

## 决策

```yaml
language: Rust
http_framework: Axum
async_runtime: Tokio
middleware: Tower + tower-http
database: PostgreSQL
database_access: SQLx
serialization: Serde
validation: Garde
openapi: utoipa
authentication:
  access_token: JWT with Ed25519
  refresh_token: Opaque Random Token
  password_hash: Argon2id
object_storage: S3-compatible
background_jobs: PostgreSQL Job Table
observability:
  logging: tracing
  metrics_and_traces: OpenTelemetry
architecture: Modular Monolith
deployment: Single Binary, Multiple Run Modes
```

## 核心不变量

任意一次账目修改：业务数据、同步日志、Mutation Receipt 同成同败。
