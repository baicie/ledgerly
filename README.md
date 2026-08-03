# Ledgerly

个人及家庭多端记账应用：Flutter Local-first 客户端 + Rust/Axum 模块化单体 + 复式记账 + Push/Pull 同步。

## 文档

从 [docs/README.md](docs/README.md) 开始。关键入口：

- [CONTEXT](docs/CONTEXT.md)
- [本轮 MVP](docs/roadmap/mvp.md)
- [ADR 索引](docs/adr/index.md)

## 仓库结构

```text
apps/client/          # Flutter
server/               # Rust + Axum (ledger-server)
packages/
  ledger_domain/      # 复式记账领域
  ledger_sync/        # 同步引擎与双设备测试
docs/
```

## 常用命令

```bash
# 领域测试
cd packages/ledger_domain && dart test

# 同步双设备测试
cd packages/ledger_sync && dart test

# Flutter 离线仓储测试
cd apps/client && flutter test

# 后端
cd server
cargo test --workspace
cargo run -- doctor
cargo run -- all   # http://0.0.0.0:8080
```

## 开发原则

每阶段：**设计 → ADR → 实现 → 验收**。分支见 [docs/roadmap/phases.md](docs/roadmap/phases.md)。
