# Phase 34 — 流式加密 bundle 与保留策略

## 1. 背景与动机

Phase 33 的加密 bundle 会把每个输入文件整体读入内存。生产 PostgreSQL dump
或大附件可能达到 GB 级，导致内存峰值不可控。同时，本地和异地 bunlde 会持续
累积，缺少统一保留策略。

本阶段把 schema v2 加密格式升级为固定大小分块，并增加 bundle 清理命令。

## 2. 目标 / 非目标

### 目标

- **G1**：每个明文文件按 1 MiB 分块；
- **G2**：每块使用独立 AES-256-GCM nonce；
- **G3**：nonce 使用随机 8-byte 前缀 + 4-byte chunk index；
- **G4**：AAD 绑定 `logicalPath + chunkIndex`；
- **G5**：备份和验证过程保持有界内存；
- **G6**：manifest 记录 chunkSize、chunkCount 和密文框架摘要；
- **G7**：无密码仍可验证密文框架、存储大小和存储 SHA-256；
- **G8**：继续读取 Phase 33 schema v1 whole-file bundle；
- **G9**：新增 bundle cleanup，只清理有效 bundle 并保留最新 N 份；
- **G10**：CI 联合演练继续覆盖创建、验证、复制、解包与恢复。

### 非目标

- 不实现并行多线程分块加密；
- 不实现断点续传或远端对象存储直传；
- 不改变 bundle 目录结构；
- 不清理无法解析 manifest 的目录；
- 不自动调度清理任务；
- 不替代 PostgreSQL WAL/PITR。

## 3. Schema v2 加密格式

```text
plaintext file
  -> chunk 0..N-1, each <= 1 MiB

payload file:
  [u32 ciphertext length][ciphertext + AES-GCM tag]
  [u32 ciphertext length][ciphertext + AES-GCM tag]
  ...
```

Nonce：

```text
random 8-byte prefix || u32 chunk index
= 12-byte AES-GCM nonce
```

AAD：

```text
logicalPath || 0x00 || u32 chunk index
```

manifest 文件项新增：

```json
{
  "chunkSizeBytes": 1048576,
  "chunkCount": 3,
  "nonceBase64": "<8-byte-prefix>"
}
```

`storedSizeBytes` 和 `storedSha256` 覆盖包含 4-byte frame length 的完整
payload。

## 4. 验证流程

### 无密码

```text
read frame lengths
  -> validate chunk count and frame lengths
  -> hash stored payload
  -> do not decrypt
  -> plaintextVerified=false
```

### 提供密码

```text
same stored-payload verification
  -> decrypt every chunk with nonce/AAD
  -> hash plaintext
  -> validate size and SHA-256
  -> plaintextVerified=true
```

## 5. 向后兼容

- schema v1：继续支持 whole-file AES-GCM 和明文 bundle；
- schema v2：新创建的 bundle 默认格式；
- `manifest.schemaVersion` 决定读取路径；
- v1 文件仍可 verify、unpack 和 replicate。

## 6. 保留策略

```bash
ledger-server bundle cleanup \
  --root /mnt/offsite/ledgerly \
  --keep 4
```

行为：

1. 扫描 root 的直接子目录；
2. 只接受可解析的 `ledgerly-server-backup-bundle` manifest；
3. 按 `createdAt` 从新到旧排序；
4. 保留最新 N 份；
5. 删除其余有效 bundle，并返回删除数量和释放字节数；
6. 跳过未知目录、无效 manifest 和符号链接。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_bundle.rs` | schema v2 分块加密、v1 兼容、cleanup |
| 2 | `main.rs` | `bundle cleanup` CLI |
| 3 | `backup_bundle_recovery.rs` | 多分块、v1 兼容、保留策略测试 |
| 4 | Runbook、路线图、设计索引 | Phase 34 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| nonce 重用 | 每文件随机前缀 + 单调 chunk index |
| 密文块换位 | AAD 绑定逻辑路径和 chunk index |
| 截断中间块 | frame 长度和 chunk count 校验 |
| 旧 bundle 无法读取 | 保留 schema v1 读取路径并加兼容测试 |
| cleanup 删除非 bundle 数据 | 只处理 direct child 且 manifest 可解析 |
| cleanup 删除符号链接 | 跳过高风险目录类型 |
| 超大文件仍占用内存 | 单块固定 1 MiB，内存不再随文件大小增长 |

## 9. 验收

- [x] schema v2 按 1 MiB 分块加密；
- [x] 大文件测试覆盖多个 chunk；
- [x] 无密码只验证密文，有密码验证明文；
- [x] schema v1 明文 bundle 继续可读；
- [x] 密文损坏和错误密码被拒绝；
- [x] bundle cleanup 只保留最新 N 份；
- [x] CI 联合恢复链路保持通过。
- [x] `cargo fmt`、Clippy、workspace tests 和 CI 全部通过。
