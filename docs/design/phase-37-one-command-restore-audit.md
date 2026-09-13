# Phase 37 — 一键加密 Bundle 恢复与审计

## 1. 背景与动机

Phase 31–36 已具备数据库 dump、对象备份、加密 bundle、异地复制、自动编排
和生产部署。但故障恢复仍需人工依次执行：

```text
verify -> unpack -> restore objects -> pg_restore -> migrate -> verify
```

手工步骤容易遗漏安全备份、顺序错误或验证不足。本阶段提供单条服务端恢复
命令，并持久化恢复审计。

## 2. 目标 / 非目标

### 目标

- **G1**：恢复前必须验证 bundle 和密码；
- **G2**：破坏性恢复前自动生成当前状态安全备份；
- **G3**：unpack 到隔离工作目录；
- **G4**：先恢复对象存储，再恢复 PostgreSQL；
- **G5**：恢复后执行 migration；
- **G6**：验证最新 schema、附件对象、附件大小和 SHA-256；
- **G7**：成功/失败写入 `RESTORE_STATUS_FILE`；
- **G8**：审计包含安全备份 runId、耗时和恢复数量；
- **G9**：CLI 必须显式 `--confirm` 才能执行；
- **G10**：`/health/backup` 返回最近恢复结果；
- **G11**：CI 联合演练改用一键恢复。

### 非目标

- 不自动回滚已恢复数据库；
- 不替代人工确认变更窗口；
- 不管理外部密钥或 KMS；
- 不支持无 `BACKUP_DIR` 的生产恢复；
- 不实现 WAL/PITR。

## 3. 恢复流程

```text
bundle verify(password)
  -> run current-state safety backup
  -> unpack bundle to BACKUP_DIR/work/restore-{id}/unpacked
  -> restore object store
  -> pg_restore database
  -> migrate
  -> verify schema + attachment metadata + object bytes
  -> write restore-status.json success
  -> remove work directory

any failure
  -> write restore-status.json failed + truncated error
  -> retain safety backup runId when already created
  -> remove work directory
```

恢复顺序选择“对象先行、数据库后行”：如果数据库恢复失败，旧数据库仍引用
的对象不会缺少；新对象额外残留比数据库指向缺失对象更安全。

## 4. 恢复后验证

- 最新索引 `uq_transactions_auto_event` 存在；
- `attachments.object_key` 对应对象必须存在；
- `size_bytes` 与对象实际大小一致；
- `content_hash` 与对象实际 SHA-256 一致；
- 记录账本数和流水数；
- 对象数量与对象备份 manifest 一致。

## 5. 恢复审计

`BACKUP_DIR/restore-status.json`：

```json
{
  "outcome": "success",
  "startedAt": "2026-09-14T00:00:00Z",
  "completedAt": "2026-09-14T00:10:00Z",
  "durationMs": 600000,
  "safetyBackupRunId": "...",
  "fileCount": 12,
  "objectCount": 4,
  "bookCount": 2,
  "transactionCount": 150,
  "errorSummary": null
}
```

`/health/backup` 的 `lastRestore` 只暴露状态、时间、耗时和聚合数量，不暴露
bundle 路径或错误详情。

## 6. CLI

```bash
export LEDGER_BACKUP_PASSWORD='use-a-long-random-password'

ledger-server bundle restore \
  --from /mnt/offsite/ledgerly/<runId> \
  --confirm

ledger-server restore-status
```

未传 `--confirm` 时命令拒绝执行。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_status.rs` | RestoreRunStatus 和 RestoreStatusStore |
| 2 | `backup_runtime.rs` | 一键恢复、安全备份、恢复后验证 |
| 3 | `health.rs` | `/health/backup.lastRestore` |
| 4 | `main.rs` | `bundle restore` / `restore-status` |
| 5 | `postgres_backup_restore.rs` | CI 改走一键恢复 |
| 6 | 设计索引、Runbook、路线图 | Phase 37 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 误触破坏性恢复 | CLI 强制 `--confirm` |
| Bundle 损坏后先破坏当前状态 | 先 verify，再创建安全备份 |
| 当前状态无法备份 | 安全备份失败时终止恢复 |
| 恢复后对象与 DB 不一致 | 逐附件校验 object key/size/hash |
| 失败后无审计 | 成败均写 restore-status |
| 健康端点泄露路径 | 只返回状态与聚合数量 |
| 安全备份占用空间 | 复用 bundle 保留清理策略 |

## 9. 验收

- [x] 一键恢复先验证 bundle 和密码；
- [x] 破坏性操作前自动创建安全备份；
- [x] 恢复后执行 migration 和附件一致性校验；
- [x] 成败均持久化恢复审计；
- [x] `/health/backup` 返回最近恢复摘要；
- [x] CLI 强制 `--confirm`；
- [ ] workspace 与 CI 联合恢复演练全部通过（待验证）。
