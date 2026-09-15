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
S3_PUBLIC_ENDPOINT=https://objects.example.com
S3_REGION=us-east-1
S3_BUCKET=ledgerly-production
S3_ACCESS_KEY_ID=replace-with-secret
S3_SECRET_ACCESS_KEY=replace-with-secret
S3_PREFIX=production/ledgerly
S3_FORCE_PATH_STYLE=false
S3_ALLOW_HTTP=false
ATTACHMENT_MAX_BYTES=104857600
```

bucket 必须预先创建，应用账号至少需要配置 prefix 下的 list、get、put、
head 和 delete 权限，并允许 CreateMultipartUpload、UploadPart、
CompleteMultipartUpload 和 AbortMultipartUpload。附件删除和失败上传清理都会
调用 DeleteObject/AbortMultipartUpload；缺少权限时，服务端会保留数据库记录
并返回对象存储错误，客户端可稍后重试。
生产建议启用 TLS、服务端加密和 bucket 版本控制。

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

## 客户端直传

S3 模式下，`attachments/upload-session` 返回：

```json
{
  "uploadMode": "direct",
  "uploadUrl": "https://objects.example.com/...presigned...",
  "uploadHeaders": {},
  "downloadMode": "direct",
  "maxSizeBytes": 104857600
}
```

客户端直接把文件 PUT 到 `uploadUrl`，完成后仍必须调用原
`attachments/{id}/complete`。complete 会 HEAD 对象、比较会话声明大小，再读取
对象校验 SHA-256。只有 complete 成功后才把附件标记为 `ready`。

超过 64 MiB 的附件使用 multipart。客户端会为每个缺失分片请求：

```http
POST /v1/books/{bookId}/attachments/{attachmentId}/parts/{partNumber}/upload-url
```

S3 可用时响应为 `uploadMode=direct`，客户端直接把 5 MiB 分片 PUT 到预签名 URL，
再用响应 `ETag` 调用同路径的 `/complete` 登记分片。缺少 `ETag`、直传不可用或
local 后端时，响应为 `uploadMode=proxy`，客户端继续走原有认证分片接口。每批最多
3 个分片并发，重试时只补缺失分片。

local 模式的 `uploadMode` 为 `proxy`，客户端继续 PUT 到 Ledgerly 的 HMAC
签名 URL，不需要改业务流程。

附件页会通过账本级目录 API 发现其他设备上传的 ready 附件，并按需下载到
本地。删除已上传附件时，客户端先调用服务端删除对象和元数据，成功后再删除
本地副本；服务端不可用时本地副本会保留以供重试。

Web bucket 建议只允许生产站点 origin：

```json
{
  "CORSRules": [{
    "AllowedOrigins": ["https://app.ledgerly.example.com"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }]
}
```

`S3_PUBLIC_ENDPOINT` 必须是客户端真实可达的地址。容器内部地址写在
`S3_ENDPOINT`，公网地址写在 `S3_PUBLIC_ENDPOINT`；两者使用同一凭证和 bucket。

附件默认上限为 100 MiB，`ATTACHMENT_MAX_BYTES` 最大可配置为 20 GiB。S3
不超过 64 MiB 的文件继续使用预签名单次 PUT；更大的文件改用 5 MiB 服务端
multipart 分片上传，S3 部署优先使用分片级预签名直传。本地对象存储超过 7 MiB
也走同一分片协议，但始终使用服务端代理，以避开 8 MiB 请求体限制。

multipart 会话会在客户端持久化。瞬时失败或应用重启后会查询已上传分片，只补传
缺失部分，最多 3 个分片并发。永久失败或自动重试耗尽时调用 abort，超时会话仍由
后台清理任务兜底。

未完成或失败的附件会在 `ATTACHMENT_PENDING_TTL_HOURS` 后由 worker 清理，
默认 24 小时、每 6 小时运行一次。清理先删除对象再删除数据库记录；若删除对象
失败，记录会保留并在下一轮重试。可通过 `attachment_cleanup_*` 指标观察结果。

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
| 分片直传成功但客户端缺少 `ETag` | bucket CORS 是否 `ExposeHeaders: ["ETag"]` |
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
