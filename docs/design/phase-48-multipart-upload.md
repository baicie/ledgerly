# Phase 48 - Multipart 大附件上传

## 1. 背景与动机

单次 S3 PUT 的对象上限是 5 GiB，本地对象存储还受服务端 8 MiB 请求体限制。
客户端此前会把整个附件读入内存，无法可靠处理更大的文件。

`object_store 0.14` 的 `Signer` 只支持普通方法加对象路径签名，不能给
`partNumber` / `uploadId` 查询参数签发分片 URL。因此本阶段采用认证分片上传：
客户端按 5 MiB 分片发送到 Ledgerly，服务端使用 S3 Multipart API 写对象。

## 2. 目标 / 非目标

### 目标

- **G1**：`ATTACHMENT_MAX_BYTES` 上限提升到 20 GiB；
- **G2**：本地对象存储超过 7 MiB、S3 超过 64 MiB 时自动切换 multipart；
- **G3**：固定 5 MiB 分片，非末片强制精确大小；
- **G4**：分片元数据持久化到 PostgreSQL，支持服务重启后 complete；
- **G5**：客户端按文件范围读取分片，不再整体加载大附件；
- **G6**：complete 复用现有 HEAD 和流式 SHA-256 校验；
- **G7**：支持显式 abort，定时清理会 AbortMultipartUpload 并删除残留对象；
- **G8**：本地模式下按顺序拼接分片并原子发布。

### 非目标

- 不提供客户端直达 S3 的 presigned part URL；
- 不支持并行分片上传；
- 不保存客户端断点偏移；失败重试会创建新 multipart 会话；
- 不改变附件列表、下载和删除协议。

## 3. API

### 创建会话

现有 `POST /attachments/upload-session` 在 multipart 模式下返回：

```json
{
  "attachmentId": "...",
  "objectKey": "books/...",
  "uploadUrl": null,
  "uploadMode": "multipart",
  "partSizeBytes": 5242880,
  "maxSizeBytes": 21474836480
}
```

### 上传分片

```http
PUT /v1/books/{bookId}/attachments/{attachmentId}/parts/{partNumber}
Authorization: Bearer ...
Content-Type: application/octet-stream
```

`partNumber` 从 1 开始。非末片必须为 5 MiB，末片按声明的总大小校验。

### 完成 / 取消

```http
POST   /v1/books/{bookId}/attachments/{attachmentId}/complete
DELETE /v1/books/{bookId}/attachments/{attachmentId}/multipart
```

## 4. 状态

`attachments` 新增：

| 字段 | 含义 |
|---|---|
| `upload_mode` | `single` / `multipart` |
| `multipart_upload_id` | S3 UploadId，本地模式为空 |
| `multipart_parts` | 已上传分片 ID 数组 |

分片 PUT 使用 PostgreSQL 行锁串行更新 parts，避免并发写入丢失。

## 5. 客户端读取

`AttachmentByteStore` 增加长度和范围读取：

- 文件平台使用 `RandomAccessFile` 读取指定区间；
- Web/内存实现使用 `sublistView`；
- 单次上传最多保留一个 5 MiB 分片在内存。

## 6. 失败与清理

- 永久失败立即 abort；
- 瞬时失败继续使用 Phase 47 的退避重试；
- 重试创建新会话，旧会话由显式 abort 或 TTL job 清理；
- 清理 job 对 multipart 行调用 AbortMultipartUpload，再幂等删除最终 key。

## 7. 验收

- [x] 20 GiB 配置上限；
- [x] multipart 会话与固定分片 API；
- [x] PostgreSQL 分片状态和行锁更新；
- [x] 本地对象顺序拼接和原子发布；
- [x] 客户端范围读取，不再整体加载大附件；
- [x] complete 复用大小与 SHA-256 校验；
- [x] abort、失败清理和 TTL 清理;
- [x] 服务端与客户端自动化测试通过。

## 8. 后续

- 并行分片上传；
- 已上传分片查询和真正的断点续传；
- 直连 S3 multipart presigned URL；
- 客户端后台任务队列。
