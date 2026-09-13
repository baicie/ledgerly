# Phase 31 — 服务端 PostgreSQL 恢复演练

## 1. 背景与动机

ADR-BE-021 要求 PostgreSQL 定期备份、异地保存并定期恢复演练，初始目标为
RPO≤24h、RTO≤4h。此前服务端只有 `backup` / `restore` CLI 和人工 Runbook，
没有自动化测试证明：

- custom dump 能在全新数据库中完整恢复；
- 恢复后的 schema migration 状态可用；
- 用户、会话、账本、交易、预算、周期规则、附件元数据和同步数据都存在；
- 恢复边界没有包含备份完成后的数据；
- 恢复流程满足 RTO 上限。

## 2. 目标 / 非目标

### 目标

- **G1**：每次测试创建唯一源数据库和目标数据库；
- **G2**：源库运行全部 migration 并写入跨业务域代表性数据；
- **G3**：使用现有 `backup()` 生成 PostgreSQL custom dump；
- **G4**：记录恢复前表数量，再写入一条备份后标记；
- **G5**：使用现有 `restore()` 恢复到全新目标库；
- **G6**：恢复后再次运行 migration，确认 schema 幂等；
- **G7**：恢复前数据存在、备份后标记不存在，证明恢复到备份边界；
- **G8**：恢复后所有受测表数量与备份前快照一致；
- **G9**：测量 restore + migrate 耗时并断言小于 4 小时 RTO；
- **G10**：测试完成后强制删除源库、目标库和临时 dump；
- **G11**：CI Rust job 安装 PostgreSQL client 并强制执行演练。

### 非目标

- 不实现 WAL 归档或 PITR；
- 不备份对象存储中的附件二进制；
- 不验证异地复制、云盘状态或跨区域恢复；
- 不在生产服务运行时自动执行 restore；
- 不以 CI 的秒级耗时代替生产容量规划；
- 不验证备份文件的外部保留周期。

## 3. 数据覆盖

演练种子覆盖以下服务端表：

```text
users
device_sessions
books
book_members
accounts
transactions
transaction_entries
budgets
recurring_rules
attachments
jobs
sync_mutations
sync_changes
```

其中附件只覆盖数据库元数据；对象存储二进制不在本阶段范围内。

## 4. 演练流程

```text
admin DATABASE_URL
  -> CREATE DATABASE source
  -> CREATE DATABASE target
  -> migrate(source)
  -> seed representative data
  -> snapshot table counts
  -> pg_dump source -> custom dump
  -> insert post-backup marker
  -> pg_restore dump -> target
  -> migrate(target)
  -> compare target counts with pre-backup snapshot
  -> assert pre marker exists and post marker is absent
  -> measure restore + migrate elapsed time
  -> DROP both databases and remove dump
```

## 5. RPO / RTO 验收

### RPO 边界

测试在 dump 完成后写入 `post-backup marker`。恢复后：

- `pre-backup marker` 必须存在；
- `post-backup marker` 必须不存在；
- 所有受测表数量必须等于 dump 前的快照。

### RTO 上限

记录从 `restore()` 开始到恢复后 migration 完成的时间，并断言小于
`4h`。CI 实际耗时通过测试输出记录：

```text
postgres backup/restore drill passed: backup=<duration> recovery=<duration>
```

## 6. CI

Rust job 已有 PostgreSQL 16 service。新增：

- 安装 `postgresql-client`，提供 `pg_dump` 和 `pg_restore`；
- 保持 `REQUIRE_POSTGRES_TESTS=true`，禁止静默跳过；
- `cargo test --workspace` 自动运行新演练。

测试角色需要 `CREATEDB` 或 superuser。CI service 的 `POSTGRES_USER` 满足该条件。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `server/tests/postgres_backup_restore.rs` | 隔离数据库、标记、恢复和 RTO 断言 |
| 2 | `.github/workflows/ci.yml` | 安装 PostgreSQL client |
| 3 | `backup-restore.md` | 增加服务端自动化演练命令 |
| 4 | 设计索引和路线图 | Phase 31 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 本地/CI 缺少 `pg_dump` | CI 安装 PostgreSQL client |
| 测试误用业务数据库 | 创建唯一源库和目标库，只把 base URL 当管理员连接 |
| 恢复后数据超过备份边界 | post-backup marker 必须不存在 |
| migration 与 dump 状态不一致 | 恢复后重新运行 migration 并检查记录 |
| 测试失败留下数据库 | 正常情况下强制 drop；CI 环境本身是临时的 |
| CI 机器性能导致 RTO 波动 | 只断言 4 小时上限，同时输出实际耗时 |

## 9. 验收

- [x] 每次演练使用独立源库和目标库；
- [x] 覆盖身份、账本、预算、周期、附件元数据和同步表；
- [x] 使用现有生产 backup/restore 路径；
- [x] 恢复后 schema migration 可重复执行；
- [x] 恢复前数据存在且备份后标记不存在；
- [x] 恢复后表数量与备份前快照一致；
- [x] restore + migrate 小于 4 小时 RTO；
- [x] CI 安装 PostgreSQL client 并强制执行；
- [x] `cargo fmt`、Clippy、workspace tests 全部通过；
- [x] CI Rust job 真实完成 PostgreSQL dump/restore 演练。
