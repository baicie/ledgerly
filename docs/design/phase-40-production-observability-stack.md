# Phase 40 - 生产观测栈与告警闭环

## 1. 背景与动机

Phase 39 已提供 Prometheus 指标、备份告警规则和接入说明，但生产主机仍需要
人工安装和配置 Prometheus、Alertmanager、Grafana。部署流水线只验收服务端健康，
无法证明指标目标正在抓取、告警规则已加载或通知渠道可用。

本阶段把观测栈作为可选、可回滚的生产运行时组件接入现有部署流程。

## 2. 目标 / 非目标

### 目标

- **G1**：提供可选 Compose profile，默认不影响现有部署；
- **G2**：固定 Prometheus、Alertmanager、Grafana 镜像版本；
- **G3**：Prometheus 自动抓取服务端、自身和 Alertmanager；
- **G4**：加载备份告警和基础平台告警；
- **G5**：Alertmanager 通过必填 webhook 投递并支持 resolved 通知；
- **G6**：Grafana 自动配置数据源和 Ledgerly Operations 仪表盘；
- **G7**：观测服务默认只绑定 `127.0.0.1`；
- **G8**：部署脚本验证服务、抓取目标、规则和 Grafana 健康；
- **G9**：CI 使用 `promtool`、`amtool`、Compose 和 JSON 校验配置；
- **G10**：提供启用、升级、验证和故障排查 Runbook。

### 非目标

- 不部署日志聚合或分布式追踪后端；
- 不实现 Prometheus/Alertmanager 多副本 HA；
- 不绑定 PagerDuty、Slack 或钉钉专有 SDK；
- 不将 Grafana 或 Prometheus 暴露到公网；
- 不替代云监控或主机级 node_exporter。

## 3. 架构

```text
ledger-server:8080/metrics
          |
          v
    Prometheus:9090
      |          |
      | rules    | scrape
      v          v
 Alertmanager  prometheus/alertmanager self metrics
      |
      v
 configured webhook

Grafana:3000 -> Prometheus datasource -> provisioned dashboard
```

所有组件加入现有 Compose 默认网络。容器间使用服务名访问，主机端口绑定
`OBSERVABILITY_BIND_ADDRESS`，默认 `127.0.0.1`。

## 4. 配置

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `OBSERVABILITY_ENABLED` | 是否在部署脚本中启用 profile | `false` |
| `OBSERVABILITY_BIND_ADDRESS` | 主机监听地址 | `127.0.0.1` |
| `PROMETHEUS_PORT` | Prometheus 主机端口 | `9090` |
| `PROMETHEUS_RETENTION` | TSDB 保留时间 | `30d` |
| `ALERTMANAGER_PORT` | Alertmanager 主机端口 | `9093` |
| `ALERTMANAGER_WEBHOOK_URL` | 告警 webhook，必填 | 无 |
| `ALERTMANAGER_SEND_RESOLVED` | 发送恢复通知 | `true` |
| `GRAFANA_PORT` | Grafana 主机端口 | `3000` |
| `GRAFANA_ADMIN_USER` | Grafana 管理员 | `admin` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana 管理员密码，必填 | 无 |
| `GRAFANA_ROOT_URL` | Grafana 外部根地址 | `http://localhost:3000` |

## 5. 告警范围

备份告警沿用 Phase 39：

- backup failed / stale / never-run；
- recovery drill failed / stale / never-run；
- 容量 warning / critical；
- 清理失败、采集失败、异地复制未启用。

新增平台告警：

- `LedgerlyServerDown`
- `LedgerlyHigh5xxRate`
- `LedgerlyHighRequestLatency`
- `LedgerlyJobFailures`
- `LedgerlyPostgresPoolSaturation`

## 6. 部署流程

```text
package runtime files
  -> copy observability directory to release
  -> read OBSERVABILITY_ENABLED from .env.prod
  -> add observability compose file and profile when enabled
  -> compose up --wait
  -> verify server health
  -> verify Prometheus ready
  -> verify Alertmanager ready
  -> verify Grafana database
  -> wait for ledgerly-server target health=up
  -> verify required alert rules loaded
  -> rollback runtime and image on failure
```

关闭 `OBSERVABILITY_ENABLED` 后，部署脚本不会加载观测 Compose 文件，已有容器和
数据卷不会被自动删除。

## 7. 安全与数据

- 所有端口默认仅监听回环地址；
- Grafana 禁止匿名访问和注册；
- Alertmanager webhook URL 在启动时校验协议和字符集；
- 指标和仪表盘不包含账本 ID、金额、路径或错误正文；
- Prometheus 数据保留在 `ledgerly_prometheus` volume；
- Alertmanager 静默和通知状态保留在 `ledgerly_alertmanager` volume；
- Grafana 状态保留在 `ledgerly_grafana` volume；
- 删除观测栈不会删除业务数据库、对象或备份 volume。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `docker-compose.observability.yml` | 三服务、profile、volume、健康检查 |
| 2 | `prometheus/prometheus.yml` | 抓取和 Alertmanager 接线 |
| 3 | `prometheus/platform-alerts.yml` | 平台告警 |
| 4 | `alertmanager/*` | webhook 配置生成与校验 |
| 5 | `grafana/*` | datasource 和仪表盘 provisioning |
| 6 | `deploy_vm_release.sh` | 可选 profile、部署验收、回滚 |
| 7 | `deploy-server.yml` | 打包、同步和配置 CI |
| 8 | `ci.yml` | 观测配置校验 job |
| 9 | Runbook / roadmap | 启用和故障处置 |

## 9. 验收

- [x] Compose profile 默认关闭且显式开启后配置有效；
- [x] Prometheus 配置和 16 条告警规则通过 `promtool`；
- [x] Alertmanager 配置通过 `amtool`；
- [x] Grafana 数据源和 8 个仪表盘 panel 可解析；
- [x] 部署脚本在启用时验证三服务、目标和规则；
- [x] 关闭观测栈不影响现有生产部署；
- [x] 全部 CI 任务通过。
