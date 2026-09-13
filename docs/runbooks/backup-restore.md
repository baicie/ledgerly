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

## 客户端灾难恢复演练

客户端使用隔离内存数据库执行四条完整恢复路径，不会读写本机正式账本：

```powershell
cd apps/client
flutter test test/application/backup_disaster_recovery_test.dart
```

演练覆盖明文全量、明文增量链、密码加密和仅外部镜像文件导入。
恢复完成后会核对全部业务域、附件字节，并确认旧同步会话已清除。

应用会记录最近 20 次恢复演练状态。成功演练 90 天后，备份策略健康中心会
提示重新演练；最近一次演练失败时也会直接提供“执行恢复演练”操作。

## 压测烟雾

```bash
# 需本机 server:8080
chmod +x scripts/loadtest_sync.sh
./scripts/loadtest_sync.sh 20
```
