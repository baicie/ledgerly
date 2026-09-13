# 备份可观测性与容量告警 Runbook

Phase 39 在现有 `/metrics` 上增加备份健康、保留容量、恢复演练和清理失败指标。
指标只使用状态、位置和结果等低基数字段，不包含数据库 URL、bundle 路径、账本
ID、金额或错误正文。

## 采集

Prometheus 可直接抓取服务端 `/metrics`：

```yaml
scrape_configs:
  - job_name: ledgerly-server
    metrics_path: /metrics
    static_configs:
      - targets: ["ledgerly-server:8080"]

rule_files:
  - /etc/prometheus/rules/ledgerly-backup-alerts.yml
```

将仓库中的
[`infrastructure/observability/prometheus/backup-alerts.yml`](../../infrastructure/observability/prometheus/backup-alerts.yml)
复制到 `rule_files` 指向的目录，并通过 `promtool check rules` 校验后重载
Prometheus。`/metrics` 应只在内网、监控网或受认证的反向代理后暴露。

## 核心指标

| 指标 | 类型 | 含义 |
|---|---|---|
| `backup_state{state}` | gauge | 备份为 `disabled / never_run / failed / stale / ready` 之一 |
| `backup_age_seconds` | gauge | 最近一次备份完成至今的秒数 |
| `backup_last_run_duration_seconds{outcome}` | gauge | 最近一次备份耗时 |
| `backup_bundle_count{location}` | gauge | 本地或异地有效 bundle 数量 |
| `backup_bundle_bytes{location}` | gauge | 本地或异地 bundle 实际占用字节 |
| `backup_bundle_invalid{location}` | gauge | 无法解析 manifest 的 bundle 目录数 |
| `backup_capacity_utilization_percent{location, severity}` | gauge | 容量阈值使用率 |
| `backup_recovery_drill_state{state}` | gauge | 恢复演练为 `disabled / never_run / failed / stale / ready` 之一 |
| `backup_recovery_drill_age_seconds` | gauge | 最近一次恢复演练完成至今的秒数 |
| `backup_restore_state{state}` | gauge | 最近一键恢复为 `never_run / failed / ready` 之一 |
| `backup_runs_total{outcome}` | counter | 当前进程完成的备份次数 |
| `backup_recovery_drill_runs_total{outcome}` | counter | 当前进程完成的恢复演练次数 |
| `backup_restore_runs_total{outcome}` | counter | 当前进程完成的一键恢复次数 |
| `backup_cleanup_failures_total{location}` | counter | 保留策略清理失败次数 |
| `backup_metrics_collection_errors_total{component}` | counter | 状态文件或容量目录采集失败次数 |

counter 在服务进程重启后从零开始，持续时间判断应使用 `rate()` 或 `increase()`；
当前状态告警应使用 gauge。

## 容量阈值

容器部署默认值为：

```dotenv
BACKUP_CAPACITY_WARN_BYTES=21474836480
BACKUP_CAPACITY_CRITICAL_BYTES=53687091200
```

阈值分别对应 20 GiB 和 50 GiB，并同时作用于本地与异地 bundle 目录。修改后需
重启服务。容量按 manifest 记录的 payload 存储字节与 manifest 文件大小计算，
包含加密后大小，但不代表文件系统块分配大小。

建议处理顺序：

1. `warning`：检查 `BACKUP_KEEP`、异常增长来源和异地卷容量，计划扩容或降低
   保留数量。
2. `critical`：先确认最新 bundle 已异地复制，再扩容、迁移目录或临时降低保留
   数量；不要直接删除最后一个已验证 bundle。
3. `backup_cleanup_failures_total` 持续增长时，优先检查目录权限、只读挂载和磁盘
   空间，再检查 bundle 目录是否存在符号链接。
4. `backup_bundle_invalid` 大于零时，检查残留的临时目录和不完整 manifest；保留
   独立副本后再人工移除无效目录。

## Alertmanager

最小路由示例：

```yaml
route:
  receiver: ledgerly-ops
  group_by: [alertname, job, location]
  routes:
    - matchers: [severity="critical"]
      receiver: ledgerly-pager
      continue: true

receivers:
  - name: ledgerly-ops
    webhook_configs:
      - url: http://alert-webhook.internal/ledgerly
  - name: ledgerly-pager
    webhook_configs:
      - url: http://pager-webhook.internal/ledgerly
```

至少应路由以下告警：

- `LedgerlyBackupFailed`
- `LedgerlyBackupStale`
- `LedgerlyRecoveryDrillFailed`
- `LedgerlyBackupCapacityCritical`

## Grafana

建议面板查询：

```promql
# 当前备份状态
backup_state == 1

# 备份与恢复演练年龄
backup_age_seconds
backup_recovery_drill_age_seconds

# 本地和异地容量
backup_bundle_bytes
backup_capacity_utilization_percent

# 最近 6 小时运行结果
sum by (outcome) (increase(backup_runs_total[6h]))
sum by (outcome) (increase(backup_recovery_drill_runs_total[6h]))

# 恢复演练实际耗时
backup_recovery_drill_last_run_duration_seconds{outcome="success"}
```

建议把 `backup_state{state="ready"} == 1`、`backup_recovery_drill_state{state="ready"} == 1`
和 `backup_capacity_utilization_percent` 放在同一时区、同一时间范围中对照，避免
只观察备份成功而遗漏不可恢复状态。

## 故障排查

```bash
curl -s http://127.0.0.1:8080/health/backup
curl -s http://127.0.0.1:8080/metrics | grep '^backup_'
```

`/health/backup` 适合一次查看结构化摘要；Prometheus 指标适合持续告警和趋势。
两者都只返回聚合状态，路径和错误详情以服务日志中的结构化事件为准。
