# S3 对象存储 Runbook

local 仍是默认后端。以下步骤用于迁移到 AWS S3 或其他 S3 兼容服务。

## 本地 S3 Mock

```bash
docker compose \
  -f infrastructure/docker/docker-compose.yml \
  --profile s3 \
  up -d
```

S3Mock `5.2.2` API 为 `http://127.0.0.1:9090`，默认创建 `S3_BUCKET`。开发客户端可
使用任意假凭据，例如 `foo` / `bar`。S3Mock 只用于本地和 CI，不可用于生产。

服务端本地环境：

```dotenv
OBJECT_STORE_BACKEND=s3
S3_ENDPOINT=http://127.0.0.1:9090
S3_REGION=us-east-1
S3_BUCKET=ledgerly
S3_ACCESS_KEY_ID=foo
S3_SECRET_ACCESS_KEY=bar
S3_PREFIX=ledgerly
S3_FORCE_PATH_STYLE=true
S3_ALLOW_HTTP=true
```

## 生产配置

```dotenv
OBJECT_STORE_BACKEND=s3
S3_ENDPOINT=https://objects.example.com
S3_REGION=us-east-1
S3_BUCKET=ledgerly-production
S3_ACCESS_KEY_ID=replace-with-secret
S3_SECRET_ACCESS_KEY=replace-with-secret
S3_PREFIX=production/ledgerly
S3_FORCE_PATH_STYLE=false
S3_ALLOW_HTTP=false
```

bucket 必须预先创建，应用账号至少需要配置 prefix 下的 list、get、put 和
head 权限。生产建议启用 TLS、服务端加密和 bucket 版本控制。

## 迁移

先停止新附件写入或进入维护窗口，然后使用 S3 配置运行 dry-run：

```bash
ledger-server object-store migrate \
  --source /var/lib/ledgerly/objects \
  --dry-run
```

确认 scanned 数量后执行：

```bash
ledger-server object-store migrate \
  --source /var/lib/ledgerly/objects
```

命令会逐对象比较 target 的大小和 SHA-256，只上传缺失或不同的对象，并在上传后
回读校验。迁移不删除本地文件。正式切换前再执行一次，确认 skipped 覆盖全部
对象。

切换 `OBJECT_STORE_BACKEND=s3` 并重启服务后：

```bash
curl -sf http://127.0.0.1:8081/health/ready
curl -sf http://127.0.0.1:8081/metrics | grep '^object_store_'
```

本地目录应至少保留一个发布周期，作为快速回退副本。回退时将
`OBJECT_STORE_BACKEND=local` 恢复并重启。

## 备份与恢复

自动备份现在会从 S3 下载对象并生成相同的加密 bundle。恢复会写回当前配置的
S3 prefix，然后逐附件校验大小和 SHA-256。

```bash
ledger-server backup-run
ledger-server bundle restore --from /mnt/offsite/ledgerly/<runId> --confirm
ledger-server recovery-drill
```

恢复演练始终使用临时本地对象目录，不会覆盖生产 bucket。

S3 不支持与本地 rename 等价的整体原子切换。恢复失败时，应检查
`restore-status.json`，修复凭据或网络问题后重新执行；恢复前的安全 bundle
仍是最终回退边界。

## 故障排查

| 现象 | 检查 |
|---|---|
| readiness 返回 `OBJECT_STORE_UNAVAILABLE` | endpoint、bucket、凭据、网络和 TLS |
| `SignatureDoesNotMatch` | access key、secret、region、系统时间 |
| S3Mock 连接失败 | 设置 `S3_FORCE_PATH_STYLE=true` 和 `S3_ALLOW_HTTP=true` |
| 附件确认返回 `UPLOAD_INCOMPLETE` | 客户端是否使用最新签名 URL，prefix 是否一致 |
| 迁移重复上传 | 目标 SHA-256 与本地是否一致，是否有并发写入 |
| 恢复中断 | 重新执行恢复，必要时先使用安全 bundle 回退数据库和对象 |

对象存储操作可从 Prometheus 查询：

```promql
sum by (operation, outcome) (rate(object_store_operations_total{backend="s3"}[5m]))
histogram_quantile(
  0.95,
  sum by (le, operation) (rate(object_store_operation_duration_seconds_bucket{backend="s3"}[5m]))
)
```
