# Phase 49 - 可恢复并行 Multipart

## 1. 背景与动机

Phase 48 的 multipart 分片按顺序上传，客户端失败后会创建新会话并从第一片重传。
对于移动网络和大文件，这会重复消耗流量。本阶段增加分片状态查询、持久化会话
提示和缺失分片补传。

## 2. 目标 / 非目标

### 目标

- **G1**：服务端返回 pending multipart 的已上传分片编号；
- **G2**：客户端持久化远端 attachment ID、上传模式和分片大小；
- **G3**：应用重启或瞬时失败后复用原 multipart 会话；
- **G4**：只上传缺失分片；
- **G5**：最多 3 个分片并发上传；
- **G6**：服务端已 ready 但客户端未收到 complete 响应时自动收敛；
- **G7**：永久失败或自动重试耗尽时 abort 并清理会话。

### 非目标

- 不提供 S3 presigned part URL；
- 不实现跨设备共享上传会话；
- 不支持更换分片大小后继续旧会话；
- 不实现动态并发自适应。

## 3. 状态查询

```http
GET /v1/books/{bookId}/attachments/{attachmentId}/multipart
```

响应：

```json
{
  "attachmentId": "...",
  "objectKey": "books/...",
  "uploadStatus": "pending",
  "uploadMode": "multipart",
  "partSizeBytes": 5242880,
  "totalParts": 4,
  "uploadedPartNumbers": [1, 3]
}
```

如果上传已经完成，`uploadStatus=ready`；客户端直接收敛为本地 ready，不再次
调用 complete。

## 4. 客户端恢复

`local_attachments` 新增：

| 字段 | 含义 |
|---|---|
| `remote_upload_mode` | 最近一次远端上传模式 |
| `remote_part_size_bytes` | multipart 分片大小 |

会话创建成功后立即写入远端 ID、object key、模式和分片大小。失败时保留这些
信息；下一次上传先查询服务端状态。

## 5. 并行上传

```text
查询已上传分片
  -> 计算缺失分片
  -> 每批最多 3 片并发读取本地范围并 PUT
  -> 全部成功后调用 complete
```

本地字节仍按范围读取，每个并发任务只持有单个分片。

## 6. 清理

- 永久错误：立即 abort，清空本地远端会话字段；
- 自动重试达到上限：abort，保留手动重试入口；
- 瞬时错误：保留会话，下一轮只补缺失分片；
- 服务端 TTL 清理继续作为进程崩溃等场景的兜底。

## 7. 验收

- [x] multipart 状态查询 API；
- [x] 客户端 v12 migration 持久化会话提示；
- [x] 重启后复用原会话并跳过已完成分片；
- [x] 每批最多 3 个分片并发上传；
- [x] 服务端 ready 状态自动收敛；
- [x] 永久失败与重试耗尽执行 abort；
- [x] 服务端和客户端自动化测试通过。

## 8. 后续

- 动态并发和带宽控制；
- 分片校验与真正的客户端直连上传；
- 后台调度器接管长时间上传；
- 跨设备上传会话恢复。
