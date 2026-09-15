# Phase 45 - 客户端附件云端上传闭环

## 1. 背景与动机

Phase 44 已完成服务端 S3 presigned 上传协议，但 Flutter 客户端只把附件
保存在本机，没有任何业务代码调用上传会话，因此用户无法实际使用直传能力。

本阶段把附件本地保存与云端上传串成完整操作链，同时保持 Local-first：
上传失败不会影响本地附件，用户可稍后重试。

## 2. 目标 / 非目标

### 目标

- **G1**：本地附件表持久化云端上传状态和远端标识；
- **G2**：新增数据库 v10 迁移，旧附件默认保持 `local`；
- **G3**：新增客户端上传服务，依次执行 create session、PUT、complete；
- **G4**：支持直传和 local proxy 两种 `uploadMode`；
- **G5**：上传失败写入本地状态并允许重试；
- **G6**：附件列表和交易附件面板提供显式“上传到云端 / 重试”操作；
- **G7**：local-only 模式不读取远端 API，界面保持原有附件能力；
- **G8**：自动化测试覆盖成功上传、失败重试状态和数据库迁移。

### 非目标

- 不自动上传用户附件，必须由用户显式触发；
- 不同步云端附件列表，因为服务端尚无 list/download API；
- 不删除服务端对象，因为服务端尚无附件删除 API；
- 备份文件不携带设备相关的远端附件 ID，恢复后重新上传即可；
- 不实现 multipart 或断点续传。

## 3. 数据模型

`local_attachments` 新增字段：

| 字段 | 含义 |
|---|---|
| `cloud_upload_status` | `local` / `uploading` / `ready` / `failed` |
| `remote_attachment_id` | 服务端附件 ID |
| `remote_object_key` | 服务端对象 key |
| `remote_upload_error` | 最近一次失败代码，不含 signed URL |

备份 payload 不包含这些设备侧字段。恢复旧备份时由数据库默认值补为
`local`，不会错误复用另一台设备的远端标识。

## 4. 上传流程

```text
用户点击“上传到云端”
  -> 读取本地附件字节
  -> 本地状态标记 uploading
  -> POST upload-session
  -> PUT uploadUrl（附带 uploadHeaders）
  -> POST complete
  -> 本地状态标记 ready + 保存远端 ID/object key
```

任一步骤失败：

```text
  -> 本地状态标记 failed
  -> 保存稳定错误代码
  -> UI 显示重试入口
```

## 5. 模式边界

- 本地模式不展示云端上传按钮，也不会实例化远端 API provider；
- 远端模式但未登录时按钮禁用，并提示登录；
- 服务端负责 Plus 权益检查，客户端不复制套餐判断规则；
- 本地附件字节始终先落盘，云端上传是可恢复的附加操作。

## 6. 验收

- [x] 数据库 v10 迁移保留旧附件并增加四个云端字段；
- [x] 上传服务完成会话、PUT、complete 全链路；
- [x] 成功状态持久化远端 attachment ID 和 object key；
- [x] 失败状态持久化稳定错误代码并可重试；
- [x] 附件页和交易附件面板提供上传/重试入口；
- [x] local-only 模式不读取远端 API；
- [x] Flutter analyze 与完整客户端测试通过。

## 7. 后续

- 服务端附件 list/download 与客户端跨设备合并；
- 附件删除时同步删除远端对象；
- 后台任务队列和自动重试；
- multipart、分片与断点续传。
