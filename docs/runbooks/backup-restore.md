# 备份与恢复 Runbook

目标（ADR-BE-021）：初始 RPO≤24h、RTO≤4h。

## 备份

```bash
export DATABASE_URL=postgres://ledgerly:ledgerly@127.0.0.1:5432/ledgerly
cargo run --manifest-path server/Cargo.toml -- backup \
  --out /tmp/ledgerly.dump \
  --objects-out /tmp/ledgerly-objects
```

建议 cron 每日执行，并将 dump 异地保存（加密可选）。

## 恢复

```bash
cargo run --manifest-path server/Cargo.toml -- restore \
  --from /tmp/ledgerly.dump \
  --objects-from /tmp/ledgerly-objects
```

恢复后执行 `cargo run -- migrate` 确认 schema，并跑 `cargo test --test postgres_flow`。

### 自动化恢复演练

先提供一个具有 `CREATEDB` 权限的 PostgreSQL 管理连接，并确保本机存在
`pg_dump` / `pg_restore`：

```bash
export DATABASE_URL=postgres://ledgerly:ledgerly@127.0.0.1:5432/ledgerly
export REQUIRE_POSTGRES_TESTS=true
cargo test --manifest-path server/Cargo.toml --test postgres_backup_restore -- --nocapture
```

测试会创建独立源库和目标库，写入恢复前/恢复后标记，执行 dump 和 restore，
同时备份并恢复对象存储附件目录，校验表数量、附件 size/SHA-256、备份边界
和 4 小时 RTO，然后删除临时数据库、对象目录与 dump 文件。

### 加密备份包与异地复制

```bash
export LEDGER_BACKUP_PASSWORD='use-a-long-random-password'

ledger-server bundle create \
  --database /tmp/ledgerly.dump \
  --objects /tmp/ledgerly-objects \
  --out /tmp/ledgerly-bundle

ledger-server bundle verify --from /tmp/ledgerly-bundle

ledger-server bundle replicate \
  --from /tmp/ledgerly-bundle \
  --to /mnt/offsite/ledgerly-bundle-2026-09-13

ledger-server bundle cleanup \
  --root /mnt/offsite \
  --keep 4
```

`LEDGER_BACKUP_PASSWORD` 丢失后无法解包，必须与备份分开保存在密钥管理系统中。
新建 bundle 使用 1 MiB 分块 AES-256-GCM；旧 schema v1 bundle 仍可验证和解包。

### 一键恢复

```bash
export LEDGER_BACKUP_PASSWORD='use-a-long-random-password'

ledger-server bundle restore \
  --from /mnt/offsite/ledgerly/<runId> \
  --confirm

ledger-server restore-status
```

恢复前会自动对当前数据库和对象存储生成安全 bundle。恢复成功后应检查
`restore-status` 和 `/health/backup.lastRestore`。失败时安全备份 runId 会保留，
可按 Runbook 回退。

### 自动备份

```bash
export BACKUP_DIR=/var/lib/ledgerly-backups
export BACKUP_OFFSITE_DIR=/mnt/offsite/ledgerly
export BACKUP_KEEP=4
export BACKUP_INTERVAL_HOURS=24
export LEDGER_BACKUP_PASSWORD='use-a-long-random-password'
```

`ledger-server worker` 或 `ledger-server all` 启动后会注册 `backup_bundle`
job，成功后自动排下一次。手工执行和查看：

```bash
ledger-server backup-run
ledger-server backup-status
curl -s http://127.0.0.1:8080/health/backup
```

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
