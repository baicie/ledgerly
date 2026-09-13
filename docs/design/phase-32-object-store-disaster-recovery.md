# Phase 32 — 对象存储附件灾备与恢复

## 1. 背景与动机

Phase 31 已证明 PostgreSQL 可以恢复到隔离数据库，但附件二进制仍只覆盖了
`attachments` 元数据。服务端附件实际保存在 `OBJECT_STORE_DIR` 的文件树中：

```text
books/{book_id}/{attachment_id}
```

如果只恢复数据库而不恢复对象目录，附件会显示为 ready，但下载会失败。
因此对象存储需要独立备份格式、完整性校验、原子恢复和跨库一致性演练。

## 2. 目标 / 非目标

### 目标

- **G1**：扫描 `OBJECT_STORE_DIR` 下所有普通文件；
- **G2**：生成带 schemaVersion 和时间戳的 manifest；
- **G3**：manifest 记录对象键、大小和 SHA-256；
- **G4**：备份时复制后重新计算元数据，避免复制过程中变更未被发现；
- **G5**：恢复前逐对象验证大小和 SHA-256；
- **G6**：恢复到同文件系统 staging 目录，再原子替换目标目录；
- **G7**：备份损坏或校验失败时不覆盖当前对象目录；
- **G8**：上传完成后把真实 size 和内容 SHA-256 写回 `attachments`；
- **G9**：CLI 支持 `backup --objects-out` 和 `restore --objects-from`；
- **G10**：PostgreSQL 恢复演练同时恢复对象目录并交叉校验附件元数据；
- **G11**：备份后新增的对象不会进入恢复结果。

### 非目标

- 不接入 AWS S3、OSS 或其他远端对象存储；
- 不做对象级增量备份；
- 不实现跨区域复制；
- 不备份数据库 WAL；
- 不处理仍在写入中的活动上传快照；
- 不替代 PostgreSQL 的备份和恢复。

## 3. 备份格式

```text
ledgerly-objects/
├── manifest.json
└── objects/
    └── books/
        └── {book_id}/
            └── {attachment_id}
```

`manifest.json`：

```json
{
  "kind": "ledgerly-object-store-backup",
  "schemaVersion": 1,
  "createdAt": "2026-09-13T00:00:00Z",
  "objectCount": 1,
  "totalSizeBytes": 32,
  "objects": [
    {
      "key": "books/book-1/attachment-1",
      "sizeBytes": 32,
      "sha256": "..."
    }
  ]
}
```

## 4. 备份流程

```text
OBJECT_STORE_DIR
  -> 拒绝符号链接
  -> 递归收集普通文件
  -> 逐对象计算 size + SHA-256
  -> 复制到备份 objects/
  -> 再计算副本 size + SHA-256
  -> 不一致则失败
  -> 原子发布 manifest.json
```

备份输出目录必须为空或不存在，避免旧对象混入新备份。

## 5. 恢复流程

```text
object backup manifest
  -> 校验 kind / schemaVersion / objectCount / totalSize
  -> 创建目标目录同级的 staging
  -> 逐对象验证源文件 size + SHA-256
  -> 复制到 staging 并再次验证
  -> 当前对象目录 rename 为 previous
  -> staging rename 为当前对象目录
  -> 成功删除 previous
```

任一步骤失败都会清理 staging；发布前失败时现有对象目录保持不变。

## 6. 数据库与对象一致性

附件上传完成后，服务端会读取对象文件并更新：

```sql
UPDATE attachments
SET upload_status = 'ready',
    size_bytes = <actual bytes>,
    content_hash = <actual SHA-256>
WHERE id = <attachment_id> AND book_id = <book_id>;
```

Phase 31 的 PostgreSQL 演练扩展为：

```text
backup PostgreSQL + backup object store
  -> insert post-backup DB marker + post-backup object
  -> restore object store + restore PostgreSQL
  -> verify attachment bytes
  -> verify attachments.content_hash / size_bytes
  -> verify post-backup object absent
```

## 7. CLI

数据库和对象存储一起备份：

```bash
ledger-server backup \
  --out /backup/ledgerly.dump \
  --objects-out /backup/ledgerly-objects
```

恢复时先验证并替换对象目录，再恢复数据库：

```bash
ledger-server restore \
  --from /backup/ledgerly.dump \
  --objects-from /backup/ledgerly-objects
```

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `object_store.rs` | manifest、备份、恢复、SHA-256、原子替换 |
| 2 | `commercial.rs` | 上传完成后回写真实 size/hash |
| 3 | `main.rs` | `--objects-out` / `--objects-from` |
| 4 | `object_store_recovery.rs` | 正常恢复与损坏保护测试 |
| 5 | `postgres_backup_restore.rs` | 数据库与附件对象联合恢复 |
| 6 | 文档索引、Runbook、路线图 | Phase 32 |

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 备份期间对象被修改 | 复制后重新计算 size/hash，不一致即失败 |
| manifest 被篡改 | 每个对象按 manifest 校验，不匹配拒绝恢复 |
| 恢复失败留下半目录 | staging 隔离，校验完成后才替换 |
| 覆盖已有对象目录后发布失败 | previous rename 回滚 |
| 符号链接逃逸对象根目录 | 备份扫描拒绝 symlink，key 禁止 `..` 和反斜杠 |
| 数据库 ready 但对象缺失 | 联合演练交叉校验元数据和二进制 |
| 对象体积大导致阻塞 | 当前同步扫描；后续阶段再引入流式任务 |

## 10. 验收

- [x] 对象存储备份包含 manifest、大小和 SHA-256；
- [x] 备份后新增对象不会进入恢复结果；
- [x] 损坏备份不会覆盖现有对象目录；
- [x] 上传完成回写真实附件 size/hash；
- [x] CLI 支持对象备份和恢复参数；
- [x] PostgreSQL 演练同时恢复并交叉校验附件对象；
- [ ] `cargo fmt`、Clippy、workspace tests 和 CI 全部通过（待验证）。
