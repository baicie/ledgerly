# Ledgerly

个人及家庭多端记账应用：Flutter Local-first 客户端 + Rust/Axum 模块化单体 + 复式记账 + Push/Pull 同步。

## 文档

从 [docs/README.md](docs/README.md) 开始。关键入口：

- [CONTEXT](docs/CONTEXT.md)
- [阶段路线图](docs/roadmap/phases.md)
- [Phase 5+/BE-6 设计](docs/design/phase-5plus-be6.md)
- [备份恢复 Runbook](docs/runbooks/backup-restore.md)

## 常用命令

```bash
# Flutter
cd apps/client && flutter test

# 后端
cd server
export DATABASE_URL=postgres://ledgerly:ledgerly@127.0.0.1:5432/ledgerly
cargo test --workspace
cargo run -- migrate
cargo run -- all

# 备份 / 压测
cargo run -- backup --out /tmp/ledgerly.dump
./scripts/loadtest_sync.sh 20
```

JWT 为 **Ed25519**（由 `JWT_ED25519_SEED` / `JWT_SECRET` 派生）。附件走本地 HMAC 对象存储（见 `.env.example`）。
