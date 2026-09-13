# Phase 35 — 自动备份编排与验证状态

## 1. 背景与动机

Phase 31–34 已具备数据库恢复、对象存储恢复、加密 bundle、异地复制和保留
策略，但每次仍需人工按顺序执行多个命令。服务端缺少：

- 定时触发；
- 完整步骤的统一编排；
- 最近成功/失败时间；
- 备份新鲜度和异地复制状态；
- 可供健康检查读取的就绪度。

本阶段把手工流程封装为 worker 可调度的 `backup_bundle` job。

## 2. 目标 / 非目标

### 目标

- **G1**：worker 启动时幂等注册 `backup_bundle` job；
- **G2**：成功后按 `BACKUP_INTERVAL_HOURS` 再排下一次；
- **G3**：每次执行完整的 dump → object backup → bundle → verify；
- **G4**：配置异地目录时执行 replicate 并再次验证；
- **G5**：本地和异地 bundle 分别执行保留清理；
- **G6**：状态原子写入 `BACKUP_DIR/status.json`；
- **G7**：状态包含成功/失败、耗时、文件数、大小和复制状态；
- **G8**：新增 `/health/backup`，区分 disabled / never_run / failed / stale / ready；
- **G9**：失败写状态后仍由 job retry 机制重试；
- **G10**：提供 `backup run` 和 `backup status` 手工命令。

### 非目标

- 不内置外部 cron；
- 不调用云厂商对象存储 API；
- 不托管密码或 KMS；
- 不在 API 请求线程执行备份；
- 不保证在线业务写入与对象备份的跨系统事务一致；
- 不实现 WAL/PITR。

## 3. 配置

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `BACKUP_DIR` | 自动备份根目录；未设置则禁用调度 | 无 |
| `BACKUP_OFFSITE_DIR` | 异地复制根目录 | 无 |
| `BACKUP_KEEP` | 本地/异地保留 bundle 数 | `3` |
| `BACKUP_INTERVAL_HOURS` | 成功后的下次执行间隔 | `24` |
| `LEDGER_BACKUP_PASSWORD` | bundle 加密密码 | 无 |

生产模式下启用 `BACKUP_DIR` 时必须设置密码。

## 4. 目录结构

```text
BACKUP_DIR/
├── status.json
├── work/
│   └── {runId}/
│       ├── database.dump
│       └── objects/
└── bundles/
    ├── {runId}/
    └── ...

BACKUP_OFFSITE_DIR/
├── {runId}/
└── ...
```

`work/` 只保存本次中间产物，执行结束后删除。

## 5. 执行流程

```text
backup_bundle job
  -> pg_dump
  -> object store backup
  -> create encrypted bundle
  -> verify bundle/ciphertext
  -> replicate to offsite dir (optional)
  -> cleanup local bundles
  -> cleanup offsite bundles
  -> write status.json success
  -> enqueue next run after interval

any step fails
  -> write status.json failed + duration + truncated error
  -> keep work cleanup best effort
  -> return error to job framework for retry/backoff
```

## 6. 健康检查

```http
GET /health/backup
```

响应示例：

```json
{
  "status": "ready",
  "intervalHours": 24,
  "ageSeconds": 3600,
  "lastCompletedAt": "2026-09-14T00:00:00Z",
  "fileCount": 12,
  "totalSizeBytes": 123456,
  "replicated": true
}
```

状态：

| 状态 | 条件 |
|---|---|
| `disabled` | 未配置 `BACKUP_DIR` |
| `never_run` | 已启用但没有状态文件 |
| `failed` | 最近一次运行失败 |
| `stale` | 最近成功时间超过 interval |
| `ready` | 最近成功且未超过 interval |

健康响应不包含 bundle 路径或错误详情。

## 7. CLI

```bash
ledger-server backup-run
ledger-server backup-status
```

这两个命令与 worker 使用同一编排函数，便于人工重跑和排障。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_runtime.rs` | 完整编排、状态写入、只读就绪度 |
| 2 | `backup_status.rs` | 状态模型、原子存储、freshness 判断 |
| 3 | `jobs.rs` | `backup_bundle` job 与自动续排 |
| 4 | `bootstrap.rs` | worker 注册和 pg_dump/restore 复用 |
| 5 | `health.rs` / `router.rs` | `/health/backup` |
| 6 | `config.rs` | 备份目录、间隔、保留数、密码 |
| 7 | `main.rs` | `backup-run` / `backup-status` |
| 8 | `backup_status.rs` test | 状态与健康端点 |

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| worker 重启重复排 job | `enqueue_if_absent` 检查 pending/running |
| 备份任务失败后不再运行 | job retry + 启动时重新注册 |
| 状态文件写入中断 | 临时文件 + rename 原子发布 |
| 健康端点泄露路径/错误 | 只返回状态和聚合数量 |
| 长时间备份阻塞 worker | 当前 MVP 接受；后续拆分专用 worker 并发 |
| 密码落入日志 | 不记录密码；配置 Debug 隐藏 |
| 保留清理删除最新 bundle | cleanup 按 createdAt 保留最新 N 份 |

## 10. 验收

- [x] 自动 backup job 幂等注册并续排；
- [x] 编排覆盖 dump、对象、bundle、verify、复制、清理；
- [x] 成功和失败都持久化状态；
- [x] `/health/backup` 支持五种就绪度；
- [x] 健康响应不包含路径和错误详情；
- [x] CLI 支持手工运行和查看状态；
- [x] workspace 测试与 CI 全部通过。
