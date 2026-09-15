# Phase 44 - S3 直传与大附件治理

## 1. 背景与动机

Phase 42 接入 S3 后，附件仍通过 Ledgerly 服务端代理上传，继承全局 8 MiB 请求
体限制，也消耗服务端带宽。S3 后端已经持有正确的对象存储凭据，因此可以直接
向客户端签发短期 URL。

本阶段为 S3 增加预签名直传和直读，同时保留 local 后端原有代理模式。

## 2. 目标 / 非目标

### 目标

- **G1**：新增 `S3_PUBLIC_ENDPOINT`，区分为服务端内部 endpoint 和客户端可达 endpoint；
- **G2**：S3 上传会话返回原生 presigned PUT URL；
- **G3**：S3 下载继续支持服务端签名，并额外返回 presigned GET URL；
- **G4**：local 后端与现有上传协议保持兼容；
- **G5**：上传会话显式返回 `uploadMode` / `downloadMode`；
- **G6**：新增 `ATTACHMENT_MAX_BYTES`，默认 100 MiB；
- **G7**：完成附件前先 HEAD 校验大小，再流式下载计算 SHA-256；
- **G8**：声明大小或最大大小不匹配时删除对象并标记附件失败；
- **G9**：直传过期、大小不匹配和完成失败写入既有审计链；
- **G10**：S3Mock CI 覆盖真实 PUT/GET presigned URL 和完成接口。

### 非目标

- 不实现大于 S3 单次 PUT 上限（5 GiB）的对象；
- 不实现 multipart 分片断点续传，留给后续阶段；
- 不向客户端提供长期 S3 凭据；
- 不允许客户端自定义任意 object key；
- 不改变账本同步协议。

## 3. 上传协议

创建上传会话后仍返回：

```json
{
  "attachmentId": "...",
  "objectKey": "books/...",
  "uploadUrl": "https://...",
  "uploadMode": "direct",
  "uploadHeaders": {},
  "downloadUrl": "https://...",
  "downloadMode": "direct",
  "expiresIn": 600,
  "maxSizeBytes": 104857600
}
```

local 后端返回同样的字段，但 mode 为 `proxy`，URL 继续指向
`/v1/object-store/{key}` HMAC 签名路由。

## 4. Endpoint 设计

| 环境变量 | 用途 | 默认 |
|---|---|---|
| `S3_ENDPOINT` | 服务端内部读写 | AWS 默认 |
| `S3_PUBLIC_ENDPOINT` | 客户端 presigned URL | 回退 `S3_ENDPOINT` |
| `ATTACHMENT_MAX_BYTES` | 单附件上限 | `104857600` |

内部和公网 endpoint 使用相同 bucket、region、凭据和 path-style 配置，但分别
缓存客户端，避免公网 URL 被改写成容器内部域名。

## 5. 完成校验

```text
POST complete
  -> lookup attachment and declared size
  -> HEAD object
  -> reject missing / too large / declared-size mismatch
  -> delete rejected object
  -> stream verify SHA-256
  -> mark attachment ready
  -> enqueue thumbnail job
```

直传 URL 只提供上传权限，不代表附件已完成。只有 complete 成功后附件才进入
`ready` 状态。

## 6. 安全

- presigned URL 只包含短期签名，不包含长期凭据；
- object key 由服务端生成，客户端不能覆盖；
- 默认 PUT TTL 600 秒、GET TTL 3600 秒；
- 客户端直传必须先通过 book membership 和 plan 检查；
- 完成接口执行 HEAD 和 SHA-256 完整性检查；
- 过大或大小不匹配的对象立即删除；
- 公网 HTTPS endpoint 不需要 `S3_ALLOW_HTTP`，开发 HTTP endpoint 必须显式开启；
- bucket 应限制 CORS 到已知 Web origin，移动端不需要浏览器 CORS。

## 7. 审计与指标

新增审计 metadata：

- `uploadMode: direct|proxy`
- `reason: upload_incomplete|size_mismatch`

对象存储指标新增：

- `sign`
- `delete`

现有 `put/get/head` 指标继续覆盖服务端访问和完成校验。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `config.rs` | public endpoint、附件上限 |
| 2 | `object_store.rs` | Signer、direct URL、HEAD size、delete |
| 3 | `commercial.rs` | 直传响应、大小校验和失败清理 |
| 4 | `s3_object_store.rs` | presigned PUT/GET 与 API complete 测试 |
| 5 | Compose / env | 公网 endpoint 和大小配置 |
| 6 | Runbook / roadmap | CORS、排错和容量说明 |

## 9. 验收

- [x] local 上传仍为 `proxy` 且兼容旧字段；
- [x] S3 上传会话返回 `direct` presigned URL；
- [x] presigned PUT/GET 可通过真实 S3Mock；
- [x] complete 同时校验 HEAD 大小和 SHA-256；
- [x] 过大或大小不一致对象会被删除；
- [x] `ATTACHMENT_MAX_BYTES` 在创建和完成阶段都生效；
- [x] 上传模式写入审计；
- [x] 全部 CI 任务通过。
