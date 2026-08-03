# 备份与恢复 Runbook

目标（ADR-BE-021）：初始 RPO≤24h、RTO≤4h。

## 备份

```bash
export DATABASE_URL=postgres://ledgerly:ledgerly@127.0.0.1:5432/ledgerly
cargo run --manifest-path server/Cargo.toml -- backup --out /tmp/ledgerly.dump
```

建议 cron 每日执行，并将 dump 异地保存（加密可选）。

## 恢复

```bash
cargo run --manifest-path server/Cargo.toml -- restore --from /tmp/ledgerly.dump
```

恢复后执行 `cargo run -- migrate` 确认 schema，并跑 `cargo test --test postgres_flow`。

## 压测烟雾

```bash
# 需本机 server:8080
chmod +x scripts/loadtest_sync.sh
./scripts/loadtest_sync.sh 20
```
