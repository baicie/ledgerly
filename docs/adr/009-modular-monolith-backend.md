# ADR-009：后端模块化单体（历史草案）

* 状态：Superseded by [ADR-019](./019-backend-stack-supersession.md) and [ADR-BE-000](./be-000-backend-architecture.md)
* 日期：2026-08-03

## 原决策（已取代）

曾提议 TypeScript + Fastify + Kysely 模块化单体。

## 取代原因

资源与正确性优先级下，正式采用 Rust + Axum。模块边界、禁止跨模块写表、PostgreSQL Job Table 等原则迁移至 ADR-BE 系列并保留。
