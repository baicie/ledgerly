# Phase 33 — 服务端加密备份包与异地复制

## 1. 背景与动机

Phase 31 和 Phase 32 分别证明了 PostgreSQL dump 与对象存储目录可以恢复，但
两者仍是分离产物：

- 无法用单个 manifest 确认一次备份包含哪些数据库与附件状态；
- dump 和对象目录可能来自不同时间点；
- 备份文件默认明文，异地保存存在泄露风险；
- 缺少统一的复制、验证和解包流程。

本阶段增加统一 bundle，把数据库 dump 与对象备份组合为可校验、可选加密、
可复制和可解包的灾备单元。

## 2. 目标 / 非目标

### 目标

- **G1**：统一逻辑路径 `database.dump` 与 `object-store/**`；
- **G2**：manifest 记录原始大小/SHA-256 和存储大小/SHA-256；
- **G3**：支持可选 AES-256-GCM 文件加密；
- **G4**：使用 Argon2id 从密码派生 256-bit 密钥；
- **G5**：每个文件使用独立随机 nonce，并把逻辑路径作为 AAD；
- **G6**：无密码时可校验密文完整性，但不能宣称明文已验证；
- **G7**：错误密码或密文损坏必须拒绝；
- **G8**：支持独立 verify、unpack、replicate 命令；
- **G9**：复制后重新验证整个 bundle；
- **G10**：PostgreSQL + 对象存储 CI 演练完整经过 bundle 加密、复制和解包。

### 非目标

- 不接入云端对象存储 API；
- 不做流式加密，当前文件会读入内存；
- 不实现多接收方密钥管理、KMS 或恢复密钥托管；
- 不替代 PostgreSQL WAL/PITR；
- 不保证备份期间数据库与对象存储的跨系统在线一致性；
- 不自动上传到远端，只复制到已挂载目录或另一文件系统。

## 3. Bundle 格式

```text
ledgerly-bundle/
├── manifest.json
└── payload/
    ├── 00000000.bin
    ├── 00000001.bin
    └── ...
```

逻辑路径：

```text
database.dump
object-store/manifest.json
object-store/objects/books/{book_id}/{attachment_id}
```

manifest 摘要：

```json
{
  "kind": "ledgerly-server-backup-bundle",
  "schemaVersion": 1,
  "createdAt": "2026-09-13T00:00:00Z",
  "encrypted": true,
  "encryption": {
    "cipher": "aes-256-gcm",
    "kdf": "argon2id",
    "saltBase64": "...",
    "memoryKiB": 19456,
    "iterations": 2,
    "parallelism": 1
  },
  "fileCount": 3,
  "totalSizeBytes": 1234,
  "files": [
    {
      "logicalPath": "database.dump",
      "payloadPath": "payload/00000000.bin",
      "sizeBytes": 1000,
      "sha256": "...",
      "storedSizeBytes": 1016,
      "storedSha256": "...",
      "nonceBase64": "..."
    }
  ]
}
```

## 4. 加密模型

```text
password + random 16-byte salt
  -> Argon2id(m=19456 KiB, t=2, p=1)
  -> 32-byte key

per file:
  random 12-byte nonce
  AES-256-GCM(key, nonce, plaintext, aad=logicalPath)
  -> ciphertext + authentication tag
```

逻辑路径作为 AAD 后，密文不能在 bundle 内被替换到其他文件路径。

> 当前实现按文件读取完整内容。超大 dump 的流式加密留待后续阶段。

## 5. CLI

创建 bundle：

```bash
export LEDGER_BACKUP_PASSWORD='use-a-long-random-password'

ledger-server bundle create \
  --database /backup/ledgerly.dump \
  --objects /backup/ledgerly-objects \
  --out /backup/ledgerly-bundle
```

验证：

```bash
ledger-server bundle verify --from /backup/ledgerly-bundle
```

复制到异地挂载目录：

```bash
ledger-server bundle replicate \
  --from /backup/ledgerly-bundle \
  --to /mnt/offsite/ledgerly-bundle-2026-09-13
```

解包后执行恢复：

```bash
ledger-server bundle unpack \
  --from /mnt/offsite/ledgerly-bundle-2026-09-13 \
  --to /restore/ledgerly

ledger-server restore \
  --from /restore/ledgerly/database.dump \
  --objects-from /restore/ledgerly/object-store
```

## 6. 验证与复制语义

### Verify

- 始终校验每个 payload 的存储大小和 SHA-256；
- 明文 bundle 同时校验逻辑大小和 SHA-256；
- 加密 bundle 提供密码后解密并校验明文摘要；
- 无密码时返回 `plaintextVerified=false`。

### Replicate

```text
verify source ciphertext integrity
  -> copy manifest + referenced payloads to staging
  -> verify staged bundle
  -> publish target
```

只有完整复制并校验成功后，目标目录才会出现。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_bundle.rs` | bundle 格式、Argon2id、AES-GCM、verify/unpack/replicate |
| 2 | `main.rs` | `bundle create/verify/unpack/replicate` CLI |
| 3 | `backup_bundle_recovery.rs` | 明文、加密、错误密码和损坏测试 |
| 4 | `postgres_backup_restore.rs` | CI 全链路 bundle 演练 |
| 5 | 文档索引、Runbook、路线图 | Phase 33 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 丢失密码导致不可恢复 | Runbook 明确密码必须由外部密钥管理保存 |
| manifest 被替换 | 加密文件使用逻辑路径 AAD，解密后校验明文摘要 |
| payload 路径逃逸 | 所有逻辑和 payload 路径禁止绝对路径、`..` 和反斜杠 |
| 复制中断生成半包 | staging 完成后才发布目标 |
| 无密码验证被误解为完整验证 | 报告明确 `plaintextVerified=false` |
| 大文件占用内存 | 文档标记限制；后续实现分块流式 AES-GCM |
| 数据库与对象非同一事务 | 备份操作窗口应停止写入，联合演练验证一致性 |

## 9. 验收

- [x] 明文 bundle 可创建、验证、复制和解包；
- [x] 加密 bundle 使用 Argon2id + AES-256-GCM；
- [x] 错误密码无法验证或解包；
- [x] payload 损坏会被发现；
- [x] 异地复制后重新验证；
- [x] PostgreSQL + 对象存储联合演练经过 bundle 全链路；
- [ ] `cargo fmt`、Clippy、workspace tests 和 CI 全部通过（待验证）。
