# Phase 42 - S3 兼容对象存储

## 1. 背景与动机

附件目前保存在 `OBJECT_STORE_DIR` 本地目录。该模式适合单机 MVP，但生产扩容、
容器替换和跨主机恢复都依赖同一块本地卷。数据库已经支持 PostgreSQL，备份也
支持异地 bundle，因此对象存储成为下一项主要生产依赖。

本阶段增加 S3 兼容后端，同时保留 local 作为开发默认和迁移源。

## 2. 目标 / 非目标

### 目标

- **G1**：增加 `OBJECT_STORE_BACKEND=local|s3`；
- **G2**：兼容 AWS S3 和其他 S3 兼容 API；
- **G3**：支持 endpoint、region、bucket、prefix、path-style 和 HTTP opt-in；
- **G4**：附件签名 URL 继续由 Ledgerly 服务端校验，不向客户端下发 S3 凭据；
- **G5**：附件 PUT/GET、存在性和 SHA-256 元数据支持 S3；
- **G6**：自动备份从 S3 导出到 bundle，恢复写回 S3；
- **G7**：恢复演练继续使用临时本地目录，不触碰生产 S3；
- **G8**：提供 local 到 S3 的 dry-run 和逐对象校验迁移命令；
- **G9**：`/health/ready` 检查对象存储连通性；
- **G10**：增加对象存储操作 counter 与 latency histogram；
- **G11**：CI 使用 S3Mock 验证真实读写、迁移、备份和恢复。

### 非目标

- 不向客户端返回云厂商原生 presigned URL；
- 不实现浏览器分片上传或断点续传；
- 不自动创建云厂商 bucket 或 IAM 策略；
- 不实现 bucket 生命周期、跨区域复制或对象锁；
- 不在 S3 恢复失败时自动重放已上传对象。

## 3. 配置

| 环境变量 | 说明 | 默认 |
|---|---|---|
| `OBJECT_STORE_BACKEND` | `local` 或 `s3` | `local` |
| `S3_ENDPOINT` | S3 兼容 endpoint，可选 | AWS 默认 |
| `S3_REGION` | S3 region | `us-east-1` |
| `S3_BUCKET` | bucket | 无 |
| `S3_ACCESS_KEY_ID` | access key | 无 |
| `S3_SECRET_ACCESS_KEY` | secret key | 无 |
| `S3_SESSION_TOKEN` | 可选临时凭据 token | 无 |
| `S3_PREFIX` | 应用对象前缀 | 无 |
| `S3_FORCE_PATH_STYLE` | 使用 path-style 请求 | `true` |
| `S3_ALLOW_HTTP` | 允许开发环境 HTTP endpoint | `false` |

S3 模式要求 bucket、access key 和 secret key。HTTP endpoint 必须显式设置
`S3_ALLOW_HTTP=true`。生产凭据应通过密钥管理或部署环境注入。

## 4. 后端抽象

对象存储客户端有两种实现：

```text
ObjectStoreClient
  Local(root)
  S3(store, prefix)
```

HTTP 附件路由继续使用 Ledgerly HMAC 签名：

```text
client -> /v1/object-store/{key} -> ObjectStoreClient -> local/S3
```

这保留了现有客户端 API、TTL 和签名语义，同时避免暴露 S3 凭据。

## 5. 备份与恢复

### 自动备份

```text
list configured object prefix
  -> download each object
  -> calculate size + SHA-256
  -> write local bundle input
  -> create encrypted bundle
```

### 一键恢复

```text
verify local bundle
  -> read each object
  -> upload to configured S3 prefix
  -> read back metadata and compare size + SHA-256
  -> restore PostgreSQL
  -> verify database attachment references against S3
```

S3 REST 没有与本地目录 rename 等价的整体原子发布。恢复前安全备份仍是主要
回退边界；失败时可重新执行恢复，已上传对象按内容哈希保持一致。

### 隔离恢复演练

演练将副本恢复到临时本地目录，并强制 `ObjectStoreBackend::Local`，不会覆盖
生产 S3。数据库业务记录和附件 manifest 仍在临时 PostgreSQL 中交叉校验。

## 6. 迁移

```text
local object directory
  -> scan and validate keys
  -> compare existing S3 object size + SHA-256
  -> upload missing or different objects
  -> read back and verify every uploaded object
```

迁移不会删除本地文件。正式切换前应停止写入或进入维护窗口，迁移完成后再次
执行，确认 skipped 数量覆盖全部对象。

## 7. 健康与指标

`/health/ready` 对 S3 执行一次轻量 `HEAD`，验证凭据、endpoint 和 bucket 可达。

指标：

```text
object_store_operations_total{backend,operation,outcome}
object_store_operation_duration_seconds{backend,operation}
```

操作包括 `put`、`get`、`head`、`list`、`backup`、`restore` 和 `migrate`。
平台告警覆盖 S3 操作失败和 p95 延迟超过两秒。

## 8. 本地与 CI

本地 Compose 增加可选 `s3` profile：

```bash
docker compose -f infrastructure/docker/docker-compose.yml --profile s3 up -d
```

CI 的 Rust job 启动固定版本 S3Mock，设置 `REQUIRE_S3_TESTS=true`，
执行真实 S3 round-trip、迁移、备份和恢复测试。

## 9. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `config.rs` | S3 backend 和配置校验 |
| 2 | `object_store.rs` | local/S3 client、迁移、备份恢复 |
| 3 | `health.rs` | readiness 对象存储检查 |
| 4 | `commercial.rs` | 附件确认使用异步后端 |
| 5 | `backup_runtime.rs` | S3 备份、恢复和演练隔离 |
| 6 | `main.rs` | `object-store migrate` CLI |
| 7 | Compose / env | S3 配置和 S3Mock profile |
| 8 | `s3_object_store.rs` | S3Mock 集成测试 |
| 9 | Runbook / roadmap | 迁移与切换流程 |

## 10. 验收

- [x] local 默认行为保持兼容；
- [x] S3 配置在缺少 bucket、凭据或 HTTP opt-in 时拒绝启动；
- [x] S3 PUT/GET、HEAD、metadata 和 prefix 正常工作；
- [x] 自动备份可导出 S3 对象；
- [x] 恢复可写回 S3 并校验 SHA-256；
- [x] 恢复演练仍使用隔离本地目录；
- [x] 迁移支持 dry-run、跳过相同对象和回读校验；
- [x] `/health/ready` 可识别不可用的对象存储；
- [x] 指标导出操作结果和延迟；
- [x] S3Mock 集成测试及全部 CI 通过。
