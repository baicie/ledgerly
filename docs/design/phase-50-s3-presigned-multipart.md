# Phase 50 - S3 分片预签名直传

## 1. 背景与动机

Phase 48/49 的 multipart 分片全部经过 Ledgerly 服务端代理。大文件并发上传会
持续占用服务端请求体、带宽和连接，S3 部署下无法充分利用对象存储的边缘入口。
Phase 50 为每个缺失分片生成独立的 SigV4 预签名 PUT URL，同时保留现有认证代理
链路作为兼容和失败回退。

## 2. 目标 / 非目标

### 目标

- **G1**：服务端使用 S3 凭证为单个 `partNumber` 和 `uploadId` 生成 10 分钟有效的
  presigned PUT URL；
- **G2**：支持 `S3_PUBLIC_ENDPOINT`、path-style、virtual-hosted、prefix 和临时
  session token；
- **G3**：客户端优先直传 S3，读取响应 `ETag` 后登记到服务端；
- **G4**：S3 直传不可用或没有 `ETag` 时回退到现有认证代理分片上传；
- **G5**：local 对象存储继续返回 `uploadMode=proxy`；
- **G6**：保留每批最多 3 个分片并发、缺失分片补传和会话恢复。

### 非目标

- 不把长期 S3 access key 下发给客户端；
- 不实现客户端自行 complete multipart；
- 不实现跨设备共享上传会话；
- 不实现动态分片大小或动态并发。

## 3. 分片 URL

```http
POST /v1/books/{bookId}/attachments/{attachmentId}/parts/{partNumber}/upload-url
```

S3 直传可用时：

```json
{
  "partNumber": 2,
  "uploadMode": "direct",
  "uploadUrl": "https://objects.example.com/...?partNumber=2&uploadId=...&X-Amz-Signature=...",
  "uploadHeaders": {},
  "expiresIn": 600,
  "totalParts": 13
}
```

local 或其他需要代理的场景：

```json
{
  "partNumber": 2,
  "uploadMode": "proxy",
  "uploadUrl": null,
  "uploadHeaders": {},
  "expiresIn": 600,
  "totalParts": 13
}
```

服务端先校验附件状态、分片编号和声明大小，再生成签名。预签名 URL 只授权指定
对象、指定 `uploadId` 和指定分片的 PUT。

## 4. ETag 登记

```http
POST /v1/books/{bookId}/attachments/{attachmentId}/parts/{partNumber}/complete
Content-Type: application/json

{
  "partId": "\"9f7c...\""
}
```

客户端直传成功后从 S3 响应读取 `ETag`，再调用该接口。服务端按 pending 状态和
分片计划校验请求，将 `partId` 写入 `multipart_parts`。complete multipart 时仍只
使用服务端已登记的分片 ID，不接受 complete 请求临时提交任意分片列表。

## 5. 客户端流程

```text
查询已上传分片
  -> 计算缺失分片
  -> 为每个缺失分片请求 upload-url
  -> direct：PUT 到 S3，读取 ETag，登记 partId
  -> proxy：调用原有 parts/{n} 代理接口
  -> 每批最多 3 个分片并发
  -> 全部成功后调用 attachment complete
```

直传响应缺少可用 `ETag` 时，客户端继续调用代理接口，确保服务端状态不会因 CORS
或兼容存储差异而无法推进。

## 6. 部署要求

- bucket CORS 的 `ExposeHeaders` 必须包含 `ETag`；
- `S3_PUBLIC_ENDPOINT` 必须是客户端可达地址；
- `S3_FORCE_PATH_STYLE=true` 时 endpoint 为 bucket 上级地址；
- virtual-hosted 自定义 endpoint 应已包含 bucket host 或 bucket path，与
  object_store 现有配置约定一致；
- 应用凭证仍需拥有 `UploadPart`、`CompleteMultipartUpload` 和
  `AbortMultipartUpload` 权限。

## 7. 验收

- [x] 分片预签名 URL 包含 `partNumber`、`uploadId` 和 `X-Amz-Signature`；
- [x] 分片 ETag 登记接口支持内存和 PostgreSQL 状态；
- [x] local 模式返回 proxy，不改变现有协议；
- [x] Flutter 直传、代理回退和恢复测试通过；
- [x] S3Mock 验证 presigned part PUT、ETag 和 complete；
- [x] 全量 Rust、Clippy 和 Flutter 测试通过。

## 8. 后续

- 根据网络质量动态调整分片并发；
- 增加 S3 ListParts 对账，识别外部上传但未登记的分片；
- 为超大附件增加带宽预算和后台调度；
- 评估多部分 checksum 与端到端完整性校验。
