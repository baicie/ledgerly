# Phase 38 — 生产定时恢复演练

## 1. 背景与动机

Phase 31–37 已具备隔离恢复、对象存储、加密 bundle、自动备份、生产部署和一键
恢复。但生产环境仍缺少持续验证：

- 最近 bundle 是否仍可解密和恢复；
- 对象与数据库是否仍保持同一快照；
- 当前 PostgreSQL 角色是否有能力创建恢复目标；
- 实际 RTO 是否仍满足目标；
- 备份成功不等于恢复就绪。

本阶段增加生产隔离恢复演练 job，不接触正式数据库或对象目录。

## 2. 目标 / 非目标

### 目标

- **G1**：worker 幂等注册 `recovery_drill` job；
- **G2**：成功后按 `RECOVERY_DRILL_INTERVAL_HOURS` 再排下一次；
- **G3**：选择最新本地或异地 bundle；
- **G4**：使用密码验证并解包 bundle；
- **G5**：创建随机临时 PostgreSQL 数据库；
- **G6**：恢复到临时对象目录；
- **G7**：验证 schema、账本、流水、附件对象、大小和 SHA-256；
- **G8**：无论成败都强制清理临时数据库和目录；
- **G9**：写入 `recovery-drill-status.json`；
- **G10**：`/health/backup.lastRecoveryDrill` 暴露最近结果；
- **G11**：提供 `recovery-drill` 和 `recovery-drill-status` CLI；
- **G12**：CI PostgreSQL 演练真实执行定时恢复演练执行器。

### 非目标

- 不演练正式数据库的原地恢复；
- 不自动 promote 临时数据库；
- 不实现 WAL/PITR；
- 不调用云厂商管理 API；
- 不代管数据库管理员密码；
- 不替代一键生产恢复命令。

## 3. 配置

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `RECOVERY_DRILL_ENABLED` | 启用定时演练 | `false` |
| `RECOVERY_DRILL_INTERVAL_HOURS` | 成功后下次间隔 | `720` |
| `RECOVERY_DRILL_DATABASE_URL` | 可选管理员连接，需 `CREATEDB` | 回退 `DATABASE_URL` |

VM Compose 的 `ledgerly` 用户默认可用于创建临时数据库。复用已有 PostgreSQL
时，应提供具有 `CREATEDB` 的管理员 URL，或关闭演练。

## 4. 演练流程

```text
latest local/offsite bundle
  -> verify + password
  -> unpack to BACKUP_DIR/work/drill-{id}
  -> verify object manifest
  -> CREATE DATABASE ledgerly_drill_{random}
  -> restore objects to work/drill-{id}/objects
  -> pg_restore into temporary DB
  -> migrate
  -> verify schema + attachments + counts
  -> DROP DATABASE ... WITH (FORCE)
  -> remove work directory
  -> write recovery-drill-status.json
```

正式 `DATABASE_URL` 只用于读取当前系统状态，不会执行 restore。对象恢复目标是
临时工作目录，不覆盖 `OBJECT_STORE_DIR`。

## 5. 状态与健康

```json
{
  "outcome": "success",
  "startedAt": "2026-09-14T00:00:00Z",
  "completedAt": "2026-09-14T00:01:30Z",
  "durationMs": 90000,
  "bundleCreatedAt": "2026-09-13T23:00:00Z",
  "fileCount": 12,
  "objectCount": 4,
  "bookCount": 2,
  "transactionCount": 150,
  "errorSummary": null
}
```

`/health/backup.lastRecoveryDrill`：

- `outcome`
- `completedAt`
- `durationMs`
- `bundleCreatedAt`
- `objectCount`
- `bookCount`
- `transactionCount`

不返回 bundle 路径或错误详情。

## 6. CLI

```bash
ledger-server recovery-drill
ledger-server recovery-drill-status
```

## 7. 调度与并发

```text
startup:
  enqueue_if_absent(recovery_drill)

job success:
  enqueue_at(now + interval)

job failure:
  existing job retry/backoff

restart after dead job:
  enqueue_if_absent finds no pending/running and recreates
```

演练在 blocking pool 中运行，避免 SQLx migration future 和重 IO 阻塞 worker
异步调度循环。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_status.rs` | RecoveryDrillStatus 和 store |
| 2 | `backup_runtime.rs` | 临时库、临时对象、恢复校验和审计 |
| 3 | `jobs.rs` | `recovery_drill` job 与续排 |
| 4 | `bootstrap.rs` | 启动注册 |
| 5 | `health.rs` | lastRecoveryDrill |
| 6 | `main.rs` | run/status CLI |
| 7 | Compose / env 示例 | 演练开关和周期 |
| 8 | `postgres_backup_restore.rs` | CI 执行演练 |

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 演练影响正式数据 | 随机临时数据库和临时对象目录 |
| 临时数据库泄漏 | `DROP DATABASE WITH (FORCE)` |
| 临时目录残留 | 工作目录 finally 清理 |
| 账号缺少 CREATEDB | 明确配置管理员 URL或失败审计 |
| 演练长期未运行 | health 暴露最近结果和 bundle 时间，外部告警 |
| 重 IO 阻塞 worker | 独立 blocking pool/runtime |
| 路径或错误泄漏 | health 只返回聚合状态 |

## 10. 验收

- [x] worker 幂等注册并续排 recovery drill；
- [x] 演练使用最新 bundle 和临时 PostgreSQL 数据库；
- [x] 使用隔离对象目录，不触碰正式对象；
- [x] 恢复后执行 schema、附件和数量校验；
- [x] 临时数据库和目录强制清理；
- [x] 成败均持久化审计；
- [x] `/health/backup` 返回 lastRecoveryDrill；
- [x] workspace 和 CI 全链路验证通过。
