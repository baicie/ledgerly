# ADR 索引

## 客户端 / 总体

| ID | 标题 | 状态 |
|----|------|------|
| [000](./000-overall-architecture.md) | 总体架构与技术基线 | Accepted |
| [001](./001-flutter-client.md) | 客户端统一使用 Flutter | Accepted |
| [002](./002-feature-first-mvvm.md) | Feature-first + MVVM + 轻量领域层 | Accepted |
| [003](./003-riverpod.md) | Riverpod 依赖与响应式状态 | Accepted |
| [004](./004-local-first.md) | Local-first 数据模型 | Accepted |
| [005](./005-drift.md) | Drift 统一数据访问 | Accepted |
| [006](./006-double-entry.md) | 复式记账模型 | Accepted |
| [007](./007-sync-protocol.md) | Push/Pull 同步协议 | Accepted |
| [008](./008-conflict-resolution.md) | 领域限定冲突处理 | Accepted |
| [009](./009-modular-monolith-backend.md) | 后端模块化单体（已由 BE 覆盖） | Superseded |
| [010](./010-postgres-authority.md) | PostgreSQL 云端权威节点 | Accepted |
| [011](./011-auth-security-privacy.md) | 认证、安全与隐私 | Accepted |
| [012](./012-routing-adaptive-ui.md) | 路由与自适应界面 | Accepted |
| [013](./013-api-contract.md) | API 契约与版本演进 | Accepted |
| [014](./014-attachment-import.md) | 附件与账单导入边界 | Accepted |
| [015](./015-repo-structure.md) | 代码仓库结构 | Accepted |
| [016](./016-testing-strategy.md) | 测试策略 | Accepted |
| [017](./017-observability.md) | 可观测性 | Accepted |
| [018](./018-release-compatibility.md) | 发布与兼容策略 | Accepted |
| [019](./019-backend-stack-supersession.md) | 后端栈以 Rust 为准 | Accepted |
| [020](./020-two-level-categories.md) | 用 Account 自引用表达两级收支分类 | Accepted |
| [021](./021-client-side-ai-insights.md) | 客户端 BYOK 调用模型生成消费总结 | Accepted |
| [022](./022-client-i18n.md) | 客户端 gen-l10n，默认中文 | Accepted |

## 后端（ADR-BE）

| ID | 标题 | 状态 |
|----|------|------|
| [BE-000](./be-000-backend-architecture.md) | 后端总体架构 | Accepted |
| [BE-001](./be-001-rust.md) | 选择 Rust | Accepted |
| [BE-002](./be-002-modular-monolith.md) | 模块化单体 | Accepted |
| [BE-003](./be-003-workspace-crates.md) | 有限 Crate 拆分 | Accepted |
| [BE-004](./be-004-single-binary.md) | 单二进制多运行模式 | Accepted |
| [BE-005](./be-005-axum-tower.md) | Axum + Tower HTTP | Accepted |
| [BE-006](./be-006-openapi-utoipa.md) | 代码优先 OpenAPI | Accepted |
| [BE-007](./be-007-postgres-sqlx.md) | PostgreSQL + SQLx | Accepted |
| [BE-008](./be-008-double-entry-server.md) | 服务端复式强约束 | Accepted |
| [BE-009](./be-009-mutation-changelog.md) | Mutation + Change Log | Accepted |
| [BE-010](./be-010-optimistic-versioning.md) | 乐观版本并发控制 | Accepted |
| [BE-011](./be-011-pull-cursor.md) | Pull 单调游标 | Accepted |
| [BE-012](./be-012-bootstrap.md) | Bootstrap 快照语义 | Accepted |
| [BE-013](./be-013-authentication.md) | JWT + Refresh Token | Accepted |
| [BE-014](./be-014-pg-job-table.md) | PostgreSQL Job Table | Accepted |
| [BE-015](./be-015-websocket-wakeup.md) | WebSocket 仅唤醒 | Accepted |
| [BE-016](./be-016-attachment-direct-upload.md) | 附件直传对象存储 | Accepted |
| [BE-017](./be-017-observability.md) | tracing + OpenTelemetry | Accepted |
| [BE-018](./be-018-low-resource.md) | 低资源部署 | Accepted |
| [BE-019](./be-019-health-shutdown.md) | 健康检查与优雅关闭 | Accepted |
| [BE-020](./be-020-migrations.md) | 显式数据库迁移 | Accepted |
| [BE-021](./be-021-backup-restore.md) | 备份和恢复 | Accepted |
| [BE-022](./be-022-testing.md) | 后端测试策略 | Accepted |
| [BE-023](./be-023-deferred-components.md) | 暂不引入的组件 | Accepted |
