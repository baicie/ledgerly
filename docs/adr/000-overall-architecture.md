# ADR-000：总体架构与技术基线

* 状态：Accepted
* 日期：2026-08-03
* 产品定位：个人及家庭多端记账、资产管理、预算与财务分析应用
* 首发平台：Android、iOS、Web
* 后续平台：Windows、macOS

## 架构目标

1. 无网络时可完整记账、查询和编辑。
2. 多设备可靠同步：不重复、不静默丢失。
3. 任意时刻可从账目明细重算账户余额。
4. 多端最大程度共享实现。
5. 支持后续家庭共享、预算、周期记账、多币种。
6. Schema 升级与长期离线不破坏数据。
7. 第一阶段保持低部署复杂度，不提前拆微服务。
8. 同步、账目与安全逻辑不依赖具体 UI 框架。

## 技术选型

```yaml
client:
  framework: Flutter
  language: Dart
  architecture: Feature-first + MVVM + Domain Layer
  state_management: Riverpod
  routing: go_router
  database: Drift
  native_database_engine: SQLite
  web_database_engine: SQLite WASM + Browser Storage
  serialization: json_serializable
  networking: Dio
  secure_storage: Platform Keychain/Keystore
  id_generation: UUIDv7

backend:
  language: Rust
  http_framework: Axum
  async_runtime: Tokio
  database: PostgreSQL
  database_access: SQLx
  architecture: Modular Monolith
  object_storage: S3-compatible
  background_jobs: PostgreSQL Job Table
  realtime: WebSocket notification (wakeup only)
  api_contract: OpenAPI via utoipa
  observability: tracing + OpenTelemetry

data:
  accounting_model: Double-entry bookkeeping
  client_model: Local-first
  synchronization: Push/Pull Cursor Protocol
  conflict_resolution: Domain-specific
  deletion: Tombstone
  amount_storage: Integer minor units
```

> 后端细节以 [ADR-BE-000](./be-000-backend-architecture.md) 为准。原 Fastify/Node 方案已被 [ADR-019](./019-backend-stack-supersession.md) 取代。

## 最终结论

Flutter Local-first 客户端 + Rust 模块化单体 + 复式记账 + Mutation/Change Log 同步。
