# Phase 43 - 安全审计与密钥轮换

## 1. 背景与动机

服务端已有结构化日志和 Prometheus 指标，但安全相关动作没有持久、可查询的
审计记录。密钥也只支持单版本，直接替换 JWT、对象 URL HMAC 或备份密码会
立即使现有令牌、URL 或备份不可用。

本阶段增加 append-only 审计事件，并为关键密钥提供重叠轮换窗口。

## 2. 目标 / 非目标

### 目标

- **G1**：新增 PostgreSQL `audit_events` 表；
- **G2**：记录认证、邀请、附件和商业变更；
- **G3**：记录 scheduled backup 和 recovery drill 结果；
- **G4**：事件包含 actor、action、outcome、target、request ID 和受限 metadata；
- **G5**：不记录密码、Token、refresh hash、对象正文或账目金额；
- **G6**：提供用户范围的分页查询 API；
- **G7**：提供运维 CLI 查询；
- **G8**：支持 JWT、对象 URL HMAC 和备份密码的 previous 值回退；
- **G9**：增加审计写入指标和 365 天默认保留策略；
- **G10**：提供密钥轮换和审计查询 Runbook。

### 非目标

- 不实现企业级 RBAC 或跨组织管理员；
- 不实现外部 SIEM 推送；
- 不提供审计事件修改或删除 API；
- 不保存原始客户端 IP 或 User-Agent；
- 不替代数据库自身的 point-in-time recovery；
- 不自动修改云厂商 IAM 密钥。

## 3. 审计模型

```text
audit_events
  id             UUIDv7 text
  occurred_at    timestamptz
  actor_type     user | system
  actor_id       user id or NULL
  action         stable action name
  outcome        success | failure | denied
  target_type    user | session | attachment | invite | subscription | job
  target_id
  request_id
  metadata       JSONB, max 4096 bytes
```

索引覆盖 actor timeline、action/outcome 和全局时间排序。审计写入失败不会回滚
主业务操作，但会增加 `audit_write_failures_total`。

## 4. 事件

初始事件：

- `auth.register`
- `auth.login`
- `auth.refresh`
- `auth.logout`
- `invite.create`
- `attachment.upload_session`
- `attachment.complete`
- `billing.upgrade`
- `backup.run`
- `backup.restore`
- `recovery_drill.run`

failure 事件的 metadata 只记录稳定 reason，例如 `invalid_credentials`、
`refresh_reuse`、`upload_incomplete`，不回显邮箱、Token 或请求正文。

## 5. 查询

用户接口：

```http
GET /v1/audit/events?limit=50&action=auth.login&before=<event-id>
```

只返回当前 actor 的事件，最大 200 条。`nextCursor` 使用 UUIDv7 作为稳定分页
游标。

运维 CLI：

```bash
ledger-server audit-query --actor <user-id> --action auth.login --limit 100
```

CLI 可查询 system 事件，主要用于备份、演练和故障排查。

## 6. 密钥轮换

### JWT

- `JWT_ED25519_PREVIOUS_SEED` 保留旧验证公钥；
- 新 token 始终用 `JWT_ED25519_SEED` 签发；
- access token TTL 为 15 分钟，因此旧 key 至少保留 15 分钟；
- refresh token 是不透明数据库 token，不受 JWT seed 影响。

### 对象 URL HMAC

- `OBJECT_STORE_HMAC_PREVIOUS_SECRET` 只用于验证；
- 新 URL 始终使用 `OBJECT_STORE_HMAC_SECRET`；
- 上传 URL TTL 10 分钟、下载 URL TTL 1 小时，旧 secret 至少保留 1 小时。

### 备份密码

- `LEDGER_BACKUP_PASSWORD_PREVIOUS` 用于打开旧 bundle；
- 新 bundle 始终使用 `LEDGER_BACKUP_PASSWORD`；
- 可在保留旧密码期间逐步恢复或重新生成旧 bundle；
- previous 密码不得写入日志或 health 响应。

### S3 凭据

S3 使用 provider 的双 access key 轮换窗口，不需要服务端保存两个 secret。
新 key 验证通过后再禁用旧 key。

## 7. 保留策略

`AUDIT_RETENTION_DAYS` 默认 365 天。worker 启动后注册
`purge_audit_events`，每天删除超期事件并续排，不提供用户侧删除接口。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `010_security_audit.sql` | audit_events、约束和索引 |
| 2 | `audit.rs` | record/query、metadata 限制 |
| 3 | auth/commercial/billing | 安全事件写入 |
| 4 | jobs/bootstrap | 系统事件和保留清理 |
| 5 | `audit.rs` HTTP | 用户分页查询 |
| 6 | config/authz/object_store | previous key 回退 |
| 7 | `backup_runtime.rs` | previous backup password |
| 8 | `main.rs` | audit-query CLI |
| 9 | Runbook / roadmap | 查询、轮换和回滚 |

## 9. 验收

- [x] 审计表迁移和索引生效；
- [x] 认证成功与失败产生结构化事件；
- [x] 附件失败不写入路径或正文；
- [x] 用户只能查询自己的审计事件；
- [x] 运维 CLI 可查询 system 事件；
- [x] JWT、HMAC 和备份密码 previous 值均有回退测试；
- [x] 审计 metadata 超过 4 KiB 时拒绝写入；
- [x] 每日保留清理续排；
- [x] 全部 CI 任务通过。
