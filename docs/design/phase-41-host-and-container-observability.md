# Phase 41 - 主机与容器资源观测

## 1. 背景与动机

Phase 40 已部署 Prometheus、Alertmanager 和 Grafana，但观测范围主要覆盖应用
指标。生产主机仍缺少以下信号：

- 根分区和外部备份盘剩余空间与 inode；
- 主机 CPU 和内存压力；
- 容器重启、CrashLoop 和 OOM；
- node-exporter / cAdvisor 自身是否可抓取。

磁盘耗尽可能同时破坏 PostgreSQL、对象存储和备份；容器 OOM 也可能在没有应用
错误日志时造成短暂不可用。因此本阶段补齐主机与容器资源层。

## 2. 目标 / 非目标

### 目标

- **G1**：新增 `node-exporter` 和 `cadvisor` 可选服务；
- **G2**：Prometheus 自动抓取两个新 target；
- **G3**：增加文件系统空间和 inode 告警；
- **G4**：增加主机 CPU 和内存压力告警；
- **G5**：增加 Ledgerly 容器重启循环和 OOM 告警；
- **G6**：增加主机与容器资源 Grafana dashboard；
- **G7**：部署验收要求两个新 target 和规则均正常；
- **G8**：CI 校验新增 Prometheus 规则和 dashboard；
- **G9**：Runbook 说明主机挂载、权限和故障排查。

### 非目标

- 不采集应用日志或分布式 trace；
- 不部署云厂商 agent；
- 不实现容器自动重启或容量扩容；
- 不替代 Phase 39 的备份 bundle 容量指标；
- 不监控 Kubernetes 集群。

## 3. 组件

### node-exporter

固定版本 `prom/node-exporter:v1.12.1`，只读挂载宿主机 `/proc`、`/sys` 和 `/`：

```yaml
--path.procfs=/host/proc
--path.sysfs=/host/sys
--path.rootfs=/rootfs
```

文件系统 collector 排除容器内部伪文件系统，保留宿主文件系统视图。

### cAdvisor

固定版本 `ghcr.io/google/cadvisor:v0.60.5`，启用：

```yaml
privileged: true
devices: [/dev/kmsg:/dev/kmsg]
```

它读取 Docker 状态和 cgroup，暴露 `container_start_time_seconds`、
`container_memory_working_set_bytes`、`container_cpu_usage_seconds_total` 和
`container_oom_events_total`。服务仍在 observability profile 内，默认不启动。

## 4. 指标与告警

新增抓取 job：

```text
node-exporter  -> node-exporter:9100
cadvisor       -> cadvisor:8080
```

新增告警：

- `LedgerlyNodeExporterDown`
- `LedgerlyCadvisorDown`
- `LedgerlyFilesystemSpaceLow`
- `LedgerlyFilesystemInodesLow`
- `LedgerlyMemoryPressure`
- `LedgerlyCpuSaturation`
- `LedgerlyContainerRestartLoop`
- `LedgerlyContainerOom`

磁盘阈值默认 85%，内存和 CPU 阈值默认 90%，容器重启告警要求 30 分钟内变化
超过一次，避免单次正常发布触发。

## 5. Dashboard

新增 `Ledgerly Host Resources`：

- 文件系统使用率；
- inode 使用率；
- 主机内存使用率；
- 主机 CPU 使用率；
- Ledgerly 容器 CPU；
- Ledgerly 容器工作集内存；
- 30 分钟容器重启次数；
- 1 小时 OOM 事件。

## 6. 部署与安全

- 两个服务严格位于 `observability` profile；
- 主机端口只绑定 `OBSERVABILITY_BIND_ADDRESS`；
- node-exporter 根挂载只读；
- cAdvisor 需要特权读取 cgroup 和 Docker 数据；
- 部署验收直接检查 two service health 和 Prometheus target；
- 规则或 target 不健康时沿用 Phase 40 回滚流程。

## 7. 配置

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `NODE_EXPORTER_PORT` | node-exporter 主机端口 | `9100` |
| `CADVISOR_PORT` | cAdvisor 主机端口 | `8082` |

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `docker-compose.observability.yml` | node-exporter / cAdvisor |
| 2 | `prometheus.yml` | 两个新 scrape job |
| 3 | `host-alerts.yml` | 8 条资源告警 |
| 4 | Grafana dashboards | Host Resources |
| 5 | `deploy_vm_release.sh` | 服务、target、规则验收 |
| 6 | `deploy_remote.sh` | 手工部署健康检查 |
| 7 | CI script | 规则和 dashboard 校验 |
| 8 | Runbook / roadmap | 配置与故障处置 |

## 9. 验收

- [x] node-exporter 暴露宿主文件系统、CPU 和内存指标；
- [x] cAdvisor 暴露 Ledgerly 容器资源指标；
- [x] 8 条资源告警可通过 `promtool`；
- [x] Host Resources dashboard 为有效 JSON 且包含 8 个 panel；
- [x] 部署验收要求 node-exporter 和 cAdvisor target 为 `up`；
- [x] 关闭 observability profile 后主机行为不变；
- [x] 全部 CI 任务通过。
