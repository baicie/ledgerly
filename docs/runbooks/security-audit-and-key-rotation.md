# 安全审计与密钥轮换 Runbook

## 查询审计

用户 API：

```bash
curl -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api.ledgerly.example.com/v1/audit/events?limit=50"
```

运维 CLI 可查询所有 actor 和 system 事件：

```bash
ledger-server audit-query --limit 100
ledger-server audit-query --actor user_... --action auth.login
ledger-server audit-query --action backup.run --outcome failure
ledger-server audit-query --before <event-id> --limit 100
```

审计 metadata 只包含稳定 reason、bookId、plan 等低敏感字段。它不保存密码、
Token、refresh hash、对象路径或账目正文。

## JWT Ed25519 轮换

1. 生成新的随机 `JWT_ED25519_SEED`。
2. 将当前 seed 临时设置为 `JWT_ED25519_PREVIOUS_SEED`。
3. 设置新的 `JWT_ED25519_SEED` 并重启 API/worker。
4. 验证新登录 token 可用，旧 access token 在 15 分钟 TTL 内仍可用。
5. 至少等待 15 分钟并观察无 `UNAUTHORIZED` 异常后删除 previous seed。

```dotenv
JWT_ED25519_SEED=new-random-seed
JWT_ED25519_PREVIOUS_SEED=old-random-seed
```

旧 seed 只用于验证，不会签发新 token。若轮换后发现客户端异常，可把 previous
重新设回主 seed 恢复旧验证能力；refresh token 是不透明数据库 token，不受此
步骤影响。

## 对象 URL HMAC 轮换

```dotenv
OBJECT_STORE_HMAC_SECRET=new-signing-secret
OBJECT_STORE_HMAC_PREVIOUS_SECRET=old-signing-secret
```

旧 secret 只用于验证，下载 URL 最长有效 3600 秒，上传 URL 最长有效 600 秒。
至少保留旧 secret 一小时，确认 `BAD_SIGNATURE` 指标没有上升后删除 previous。

## 备份密码轮换

```dotenv
LEDGER_BACKUP_PASSWORD=new-backup-password
LEDGER_BACKUP_PASSWORD_PREVIOUS=old-backup-password
```

新 bundle 使用新密码，恢复和演练会自动尝试当前密码与 previous 密码。轮换流程：

1. 设置 current/previous 并重启 worker/API。
2. 运行 `ledger-server recovery-drill`，确认旧 bundle 仍可恢复。
3. 生成一个使用新密码的 bundle，再执行一次恢复演练。
4. 等旧 bundle 超出保留范围后移除 previous。

不要把密码写入 Runbook、Issue、日志或 Prometheus label。密码应保存在密钥管理
系统中，并与备份文件分开保存。

## S3 凭据轮换

1. 在 S3 provider 创建第二组 access key。
2. 更新 `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` 并重启服务。
3. 检查 `/health/ready` 和对象存储操作错误率。
4. 运行 `object-store migrate --dry-run` 验证 list/head 权限。
5. 确认稳定后禁用旧 access key。

应用不需要同时持有两组 S3 secret，provider 的双 key overlap window 负责轮换。

## 审计保留

```dotenv
AUDIT_RETENTION_DAYS=365
```

worker 每天执行一次 `purge_audit_events`。审计表为 append-only 使用模式，不提供
修改或删除 API。若法规要求更长保留，可提高该值，并由数据库备份覆盖审计记录。

审计写入失败：

```promql
increase(audit_write_failures_total[10m]) > 0
```

此时主业务仍会继续，但应检查 PostgreSQL 权限、磁盘和表约束。
