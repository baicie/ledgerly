# ADR-019：后端技术栈以 Rust + Axum 为准

* 状态：Accepted
* 日期：2026-08-03
* 取代：[ADR-009](./009-modular-monolith-backend.md) 中的 Fastify/Node 选型

## Context

总体草案曾写 TypeScript + Fastify；后端专项 ADR 基于「正确性 > 低资源 > 稳定性 > 速度」选择 Rust。

## Decision

正式后端栈：

```text
Rust + Axum + Tokio + Tower + SQLx + PostgreSQL
```

模块化单体、Job Table、Mutation 同步等产品原则保留，实现语言与框架以 ADR-BE 系列为准。

## Consequences

- 仓库使用 `server/` Cargo workspace，而非 pnpm Node server。
- OpenAPI 由 utoipa 从 Rust DTO 生成。
- 部署形态为 `ledger-server` 单二进制多模式。
