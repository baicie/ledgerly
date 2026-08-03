# Ledgerly

个人及家庭多端记账应用：Flutter Local-first 客户端 + Rust/Axum 模块化单体 + 复式记账 + Push/Pull 同步。

## 文档

从 [docs/README.md](docs/README.md) 开始。关键入口：

- [CONTEXT](docs/CONTEXT.md)
- [本轮 MVP](docs/roadmap/mvp.md)
- [ADR 索引](docs/adr/index.md)

## 仓库结构（目标）

```text
apps/client/     # Flutter
server/          # Rust + Axum
packages/        # Dart packages（ledger_domain 等）
docs/
infrastructure/
```

## 开发原则

每阶段：**设计 → ADR → 实现 → 验收**。详见 [docs/roadmap/mvp.md](docs/roadmap/mvp.md)。
