# 生产观测栈 Runbook

观测栈默认关闭，只影响显式启用它的部署。Prometheus、Alertmanager 和 Grafana
的默认主机端口全部绑定到 `127.0.0.1`。

## 启用

在 `/opt/ledgerly/.env.prod` 中设置：

```dotenv
OBSERVABILITY_ENABLED=true
OBSERVABILITY_BIND_ADDRESS=127.0.0.1
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=30d
ALERTMANAGER_PORT=9093
ALERTMANAGER_WEBHOOK_URL=https://alerts.example.com/ledgerly
ALERTMANAGER_SEND_RESOLVED=true
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=use-a-long-random-password
GRAFANA_ROOT_URL=http://localhost:3000
```

`ALERTMANAGER_WEBHOOK_URL` 必须是没有空白、双引号或反斜杠的 HTTP(S) URL。
部署流水线会同步观测配置、加载 Compose profile，并验证：

- Ledgerly `/metrics` target 为 `up`；
- 必需备份和平台告警已加载；
- Prometheus、Alertmanager 和 Grafana 健康；
- Grafana 数据库可用。

部署失败时使用现有运行时和镜像回滚，不会自动删除观测数据卷。

## 手工启动

在 VM 的 `/opt/ledgerly/runtime-current` 目录执行：

```bash
COMPOSE_PROJECT_NAME=ledgerly docker compose \
  --profile observability \
  -f observability/docker-compose.observability.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.vm.yml \
  --env-file /opt/ledgerly/.env.prod \
  up -d --wait --wait-timeout 180
```

停止观测服务但保留数据：

```bash
COMPOSE_PROJECT_NAME=ledgerly docker compose \
  --profile observability \
  -f observability/docker-compose.observability.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.vm.yml \
  --env-file /opt/ledgerly/.env.prod \
  stop prometheus alertmanager grafana
```

不要在未确认数据迁移方案前执行 `down -v`。

## 访问

服务默认不对外暴露。通过 SSH 隧道访问：

```bash
ssh -N \
  -L 9090:127.0.0.1:9090 \
  -L 9093:127.0.0.1:9093 \
  -L 3000:127.0.0.1:3000 \
  ubuntu@82.156.234.84
```

然后打开：

- Prometheus: `http://127.0.0.1:9090`
- Alertmanager: `http://127.0.0.1:9093`
- Grafana: `http://127.0.0.1:3000`

如需通过反向代理长期访问，必须增加 TLS、身份认证和网络访问控制，不能直接
把这三个端口绑定到公网。

## 告警投递测试

向 Alertmanager 注入一条 10 分钟后过期的测试告警：

```bash
ends_at=$(date -u -d '+10 minutes' '+%Y-%m-%dT%H:%M:%SZ')
curl -fsS -X POST http://127.0.0.1:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d "[{\"labels\":{\"alertname\":\"LedgerlyDeliveryTest\",\"severity\":\"warning\"},\"annotations\":{\"summary\":\"delivery test\"},\"endsAt\":\"${ends_at}\"}]"
```

确认接收端收到通知后，可在 Alertmanager UI 中创建静默，或等待 `endsAt`
自动过期。

## 配置校验

在仓库根目录执行：

```bash
scripts/tests/observability_config_test.sh
```

该脚本校验 Compose 合并、Prometheus 配置和规则、Alertmanager 配置以及 Grafana
仪表盘 JSON。CI 的 `Observability config` job 会重复执行同一组检查。

## 故障排查

```bash
COMPOSE_PROJECT_NAME=ledgerly docker compose \
  --profile observability \
  -f /opt/ledgerly/runtime-current/observability/docker-compose.observability.yml \
  -f /opt/ledgerly/runtime-current/docker-compose.prod.yml \
  -f /opt/ledgerly/runtime-current/docker-compose.vm.yml \
  --env-file /opt/ledgerly/.env.prod \
  ps

docker logs --tail=150 ledgerly-prometheus
docker logs --tail=150 ledgerly-alertmanager
docker logs --tail=150 ledgerly-grafana
```

常见问题：

| 现象 | 排查 |
|---|---|
| Prometheus target `down` | 检查服务端 `/metrics`、Compose 网络和 `LEDGER_LISTEN` |
| 规则未加载 | 检查 `promtool`，然后查看 Prometheus rule API 和日志 |
| Alertmanager 启动失败 | 检查 webhook URL 是否满足字符和协议要求 |
| Grafana 没有面板 | 检查 datasource/dashboard provisioning 挂载和容器日志 |
| 磁盘持续增长 | 检查 `PROMETHEUS_RETENTION` 和 `ledgerly_prometheus` volume |

## 备份与升级

- Prometheus TSDB 可降级为监控缓存，不要求恢复后再部署；
- Alertmanager volume 保存静默和通知状态，升级时保留；
- Grafana volume 保存本地用户和状态，升级时保留；
- 升级前记录 `.env.prod`，再走一次正常部署，失败由部署脚本回滚运行时和镜像；
- 若明确要清空监控历史，单独删除对应 volume，禁止删除业务和备份 volume。
