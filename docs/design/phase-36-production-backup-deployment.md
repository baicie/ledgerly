# Phase 36 — 生产备份部署接线与监控

## 1. 背景与动机

Phase 35 已实现自动备份编排和 `/health/backup`，但生产部署模板尚未接线：

- 运行镜像没有 `pg_dump` / `pg_restore`；
- Compose 没有备份目录和异地挂载点；
- `.env.prod` 没有备份密码和保留配置；
- 部署验收只检查 `/health/ready`；
- CI 没有构建服务端镜像并验证备份工具。

本阶段把自动备份完整接入生产部署。

## 2. 目标 / 非目标

### 目标

- **G1**：运行镜像使用 PostgreSQL 16 客户端；
- **G2**：镜像预建 objects / backups / offsite 可写目录；
- **G3**：Compose 挂载三类持久卷；
- **G4**：异地挂载点支持 named volume 或绝对宿主机路径；
- **G5**：`.env` 示例包含备份密码、间隔和保留数；
- **G6**：部署验收检查 `/health/backup` schema 和状态；
- **G7**：部署验收检查备份和异地目录可写；
- **G8**：部署验收要求服务镜像内 `pg_dump --version` 为 16；
- **G9**：PR CI 构建服务端镜像并执行 smoke test；
- **G10**：发布 Runbook 说明首次启用和状态检查。

### 非目标

- 不自动配置云厂商对象存储；
- 不代管密码或 KMS；
- 不自动挂载宿主机外接磁盘；
- 不替代外部 Prometheus/告警系统；
- 不改变 API 的 `/health/ready` 响应。

## 3. 运行镜像

```text
postgres:16-bookworm
  + curl / ca-certificates
  + ledgerly uid 10001
  + /var/lib/ledgerly/objects
  + /var/lib/ledgerly/backups
  + /var/lib/ledgerly/backups-offsite
```

使用 PostgreSQL 16 镜像作为运行时基线，保证 `pg_dump` 版本不低于服务端
PostgreSQL 16。

## 4. Compose 接线

```yaml
environment:
  BACKUP_DIR: /var/lib/ledgerly/backups
  BACKUP_OFFSITE_DIR: /var/lib/ledgerly/backups-offsite
  BACKUP_KEEP: 4
  BACKUP_INTERVAL_HOURS: 24
  LEDGER_BACKUP_PASSWORD: ...

volumes:
  - ledgerly_objects:/var/lib/ledgerly/objects
  - ledgerly_backups:/var/lib/ledgerly/backups
  - ${BACKUP_OFFSITE_HOST_MOUNT:-ledgerly_backups_offsite}:/var/lib/ledgerly/backups-offsite
```

默认 `BACKUP_OFFSITE_HOST_MOUNT` 是 named volume。生产异地保存时设置绝对
宿主机路径，例如 `/mnt/backup-disk/ledgerly`。

## 5. 部署验收

部署脚本按顺序验证：

1. `/health/ready` 返回 PostgreSQL ready；
2. `/health/backup` 返回允许状态且不包含路径/错误详情；
3. objects 目录可写；
4. backups 目录可写；
5. backups-offsite 目录可写；
6. `pg_dump` 和 `pg_restore` 主版本为 16；
7. schema index 数量正确。

备份状态不是部署硬门禁：首次部署允许 `never_run`，已有失败允许
`failed`，过期允许 `stale`，但会打印 WARNING。部署必须确保状态端点可用且
配置未 disabled。

## 6. CI 与镜像 smoke

新增 `Server image` CI job：

```text
docker buildx build --load
  -> scripts/tests/server_image_smoke_test.sh
```

smoke test 验证：

- 容器用户 UID 10001；
- objects / backups / offsite 三个卷可写；
- `pg_dump --version` 为 PostgreSQL 16；
- `pg_restore --version` 为 PostgreSQL 16。

## 7. 监控建议

外部监控至少采集：

- `/health/ready`：服务与数据库可用；
- `/health/backup.status`：ready / stale / failed / never_run / disabled；
- `backup.ageSeconds` 与 `BACKUP_INTERVAL_HOURS`；
- `replicated`；
- `fileCount` / `totalSizeBytes` 的趋势。

建议告警：

- `failed` 立即告警；
- `never_run` 持续超过一个 interval；
- `stale` 告警；
- `replicated=false` 且配置了异地目录时告警。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `server/Dockerfile` | PostgreSQL 16 客户端和备份目录 |
| 2 | `docker-compose.prod.yml` | 备份卷、异地挂载点、环境变量 |
| 3 | `env.prod.example` / `env.vm.example` | 密码、间隔、保留、挂载配置 |
| 4 | `deploy_vm_release.sh` | `/health/backup` 与卷/pg_dump 验收 |
| 5 | `deploy_vm_release_test.sh` | 健康 JSON 校验测试 |
| 6 | `server_image_smoke_test.sh` | 备份工具与卷权限测试 |
| 7 | `ci.yml` | 服务端镜像 build/smoke job |
| 8 | `deploy-server.yml` | PostgreSQL client 测试环境 |
| 9 | 发布 Runbook、路线图、设计索引 | Phase 36 |

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| pg_dump 版本低于服务端 | 运行时基线固定 PostgreSQL 16 |
| 备份卷不可写 | 镜像预建目录，部署脚本写测试 |
| 异地目录实际仍在同盘 | 支持绝对宿主机挂载路径并写 Runbook |
| 部署因历史 backup failed 阻塞 | 状态只警告，不阻断发布 |
| 密码进入日志 | Compose env secret，不输出配置 |
| 健康响应泄露路径 | smoke 校验敏感字段不存在 |
| 镜像变大 | 接受；换取 PostgreSQL 16 工具兼容性 |

## 10. 验收

- [x] 运行镜像含 PostgreSQL 16 客户端；
- [x] objects / backups / offsite 三个卷可写；
- [x] Compose 和环境示例完成接线；
- [x] 部署脚本验证 `/health/backup`；
- [x] 部署脚本验证备份目录和 pg_dump 版本；
- [x] PR CI 构建并 smoke test 服务端镜像；
- [ ] workspace、镜像 smoke 和部署 workflow 全部通过（待验证）。
