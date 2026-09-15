# Phase 39 - 备份告警与容量治理

## 1. 背景与动机

Phase 35-38 已提供自动备份、一键恢复和定时隔离演练，并通过
`/health/backup` 暴露最终状态。但生产告警仍缺少可直接接入 Prometheus 的
时间序列：

- 备份年龄和恢复演练年龄无法绘制趋势；
- 本地与异地 bundle 数量、实际占用和增长速率不可见；
- 最近一次失败后缺少可聚合的 outcome counter；
- 保留清理失败和指标采集失败没有独立信号；
- 容量阈值只在人工检查磁盘时才能发现。

本阶段不改变备份或恢复语义，只补齐观测、容量阈值和告警接线。

## 2. 目标 / 非目标

### 目标

- **G1**：在 `/metrics` 增加备份、恢复、恢复演练和容量指标；
- **G2**：状态指标保持低基数，不包含路径、ID、金额和错误正文；
- **G3**：备份、恢复和演练完成时累加 outcome counter；
- **G4**：本地和异地 bundle 分开统计数量、实际字节和无效目录；
- **G5**：清理失败和状态采集失败分别计数；
- **G6**：增加 `BACKUP_CAPACITY_WARN_BYTES` 与
  `BACKUP_CAPACITY_CRITICAL_BYTES`；
- **G7**：提供可直接加载的 Prometheus 告警规则；
- **G8**：Runbook 提供 Prometheus、Alertmanager 和 Grafana 示例；
- **G9**：集成测试验证 `/metrics` 输出。

### 非目标

- 不实现 Prometheus、Alertmanager 或 Grafana 容器编排；
- 不自动删除超过容量阈值的 bundle；
- 不改变 `BACKUP_KEEP` 的保留语义；
- 不暴露原始错误、bundle 路径或对象 key；
- 不持久化进程内 counter 的累计值。

## 3. 指标模型

### 状态 gauge

```text
backup_state{state="disabled|never_run|failed|stale|ready"}
backup_recovery_drill_state{state="disabled|never_run|failed|stale|ready"}
backup_restore_state{state="never_run|failed|ready"}
```

每个状态族一次只有一个 `state` 为 `1`，其余为 `0`。这样告警规则不依赖
缺失样本，也能区分“未启用”和“启用但从未运行”。

### 运行 gauge

```text
backup_age_seconds
backup_last_run_timestamp_seconds{outcome}
backup_last_run_duration_seconds{outcome}
backup_recovery_drill_age_seconds
backup_recovery_drill_last_run_timestamp_seconds{outcome}
backup_recovery_drill_last_run_duration_seconds{outcome}
backup_restore_age_seconds
backup_restore_last_run_timestamp_seconds{outcome}
backup_restore_last_run_duration_seconds{outcome}
```

状态文件不存在时，年龄和耗时归零，对应 state 为 `never_run`。

### 容量 gauge

```text
backup_bundle_count{location="local|offsite"}
backup_bundle_bytes{location="local|offsite"}
backup_bundle_invalid{location="local|offsite"}
backup_replication_enabled
backup_capacity_limit_bytes{location,severity}
backup_capacity_utilization_percent{location,severity}
```

容量按 manifest 记录的 payload 存储字节与 manifest 文件大小求和，不采用业务
明文大小或文件系统块分配大小。warning 和 critical 阈值同时应用于本地和异地
目录，避免在每次抓取时遍历所有 payload。

### Counter

```text
backup_runs_total{outcome="success|failure"}
backup_recovery_drill_runs_total{outcome}
backup_restore_runs_total{outcome}
backup_cleanup_failures_total{location}
backup_metrics_collection_errors_total{component}
```

Counter 由当前进程维护，重启后归零。告警和趋势判断使用 `rate()` 或
`increase()`，持久状态由 status.json 和 `backup_state` 提供。

## 4. 采集流程

```text
GET /metrics
  -> read status.json
  -> read recovery-drill-status.json
  -> read restore-status.json
  -> scan BACKUP_DIR/bundles
  -> scan BACKUP_OFFSITE_DIR
  -> set state / age / duration / storage / capacity gauges
  -> render Prometheus text
```

采集按组件隔离错误。单个状态文件损坏或目录不可读时增加
`backup_metrics_collection_errors_total`，其余指标继续导出。

## 5. 容量配置

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `BACKUP_CAPACITY_WARN_BYTES` | warning 阈值 | `21474836480`（20 GiB） |
| `BACKUP_CAPACITY_CRITICAL_BYTES` | critical 阈值 | `53687091200`（50 GiB） |

critical 必须大于等于 warning，二者都必须大于零。

## 6. 告警规则

规则文件：

```text
infrastructure/observability/prometheus/backup-alerts.yml
```

覆盖：

- 备份 failed / stale / never-run；
- 恢复演练 failed / stale / never-run；
- 本地或异地容量 warning / critical；
- 保留清理失败；
- 指标采集失败；
- 启用备份但未配置异地复制。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `config.rs` | 容量阈值和校验 |
| 2 | `metrics.rs` | 指标描述和 recorder API |
| 3 | `backup_bundle.rs` | bundle 目录容量统计 |
| 4 | `backup_runtime.rs` | 状态采集与运行 counter |
| 5 | `router.rs` | `/metrics` 抓取时刷新备份指标 |
| 6 | `backup-alerts.yml` | Prometheus 告警规则 |
| 7 | `backup-observability.md` | 采集、告警和 Grafana Runbook |
| 8 | `backup_metrics.rs` | `/metrics` 集成测试 |
| 9 | Compose / env examples | 阈值默认值 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 抓取时扫描目录产生 I/O | 每次只遍历保留的少量 bundle 目录和文件 |
| 指标标签基数膨胀 | 只允许静态 state、location、severity、outcome、component |
| 状态文件损坏导致全端点失败 | 按组件捕获错误并暴露采集失败 counter |
| 重启导致 counter 归零 | 状态告警使用 gauge，counter 只用于速率 |
| 告警依赖外部监控栈 | 保留 `/health/backup` 作为无 Prometheus 降级路径 |
| 误删最后一个备份 | 容量告警只提供信号，不自动删除 |

## 9. 验收

- [x] `/metrics` 导出备份、恢复和演练状态；
- [x] 本地与异地 bundle 数量、字节和无效目录可见；
- [x] 容量阈值可通过环境变量配置并校验顺序；
- [x] 运行结果、清理失败和采集失败具有 counter；
- [x] 告警规则可由 `promtool check rules` 校验；
- [x] Runbook 包含 Prometheus、Alertmanager 和 Grafana 示例；
- [x] workspace 测试和五项 CI 全绿。
