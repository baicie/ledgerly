# Phase 9 — 附件二进制打包 (Attachment Binary Bundling)

## 1. 背景与动机

Phase 6 落地了"全应用快照"备份，但**只备份附件元数据**（`LocalAttachmentRepository` 表的 `relativePath` 引用），**二进制文件本身没有被打包**：

```json
{
  "attachments": [
    {
      "id": "f1e8...",
      "bookId": "personal",
      "transactionId": "tx_001",
      "fileName": "receipt.jpg",
      "mimeType": "image/jpeg",
      "relativePath": "attachments/f1e8...bin",
      "createdAt": "..."
    }
  ]
}
```

恢复后 `relativePath` 指向的文件**根本不存在**，用户看到的是空白的附件缩略图。Phase 6 设计文档明确把"不做附件二进制（仅备份元数据，文件实体需手动复制）"列为**非目标**。

真实场景：

| 已有 | 缺失 |
|---|---|
| 备份含附件元数据 | 备份含附件二进制 |
| 恢复后元数据记录存在 | 恢复后图片/扫描件能打开 |
| 跨设备迁移骨架完整 | 跨设备迁移附件完整 |

设计目标：把 Phase 6 设计文档非目标里这一项补完，让"备份能恢复"这个最朴素的承诺真正成立。

## 2. 目标 / 非目标

### 目标
- **G1**：导出备份时把所有附件二进制打包进 `.ledgerly.zip` 容器内 `attachments/<id>.bin`；
- **G2**：envelope 增加 `attachmentIndex` 字段（数组，列出每个附件的 `id` / `relativePath` / `size` / `sha256` / `mime`），无需解析 zip 即可在恢复预览里显示"N 个附件，共 M MB"；
- **G3**：恢复时把 zip 里的附件二进制写回 `AttachmentStore`，按 `relativePath` 落地；
- **G4**：`schemaVersion` 升级到 `2`，老 v1 文件（`.ledgerly.json`）仍能读取（只读模式，不含附件二进制，UI 提示"附件不会恢复"）；
- **G5**：widget 测试覆盖：导出后 `attachmentIndex` 完整 / 恢复后附件字节相同 / 老 v1 文件仍可读。

### 非目标
- 不做增量 diff（每次全量打包附件）；
- 不做加密附件（独立阶段）；
- 不做跨设备断点续传；
- 不压缩附件（图片/扫描件已部分压缩，gzip 收益小）；
- 不改 attachment UI（Phase 9 只动 backup 通路）。

## 3. 设计

### 3.1 备份格式升级

文件扩展名从 `.ledgerly.json` 改为 `.ledgerly.zip`（压缩包容器）：

```
ledgerly-backup-2026-09-13_1415.ledgerly.zip
├── manifest.json       # envelope（kind, schemaVersion=2, exportedAt, deviceId, summary, bookIds, attachmentIndex）
├── data.json           # 原 payload（账本/账户/分类/交易/分录/规则/预算/附件元数据）
└── attachments/
    ├── <attachment-id>.bin
    └── ...
```

`schemaVersion: 2` 让老备份仍然可以读——`BackupDocument.fromEnvelope` 不带 zip，仍然能用 JSON envelope 解析。Restore 端如果 envelope 是 v1，UI 在预览里加一条提示：

> "该备份是 schema v1，不含附件二进制。"

### 3.2 服务层改造

新增抽象 `AttachmentSourcePort`，让 `BackupService` 不直接耦合到 `AttachmentStore`：

```dart
abstract class AttachmentSourcePort {
  Future<List<AttachmentSourceEntry>> listAll({Set<String>? bookIds});
  Future<Uint8List?> readBytes(String relativePath);
}

class AttachmentSourceEntry {
  final String id;
  final String relativePath;
  final int size;
  final String sha256;
  final String? mime;
}
```

`BackupService.export()` 流程：

```dart
Future<BackupDocument> export({Set<String>? bookIds}) async {
  ...
  final attachmentMetas = await scoped<LocalAttachmentRecord>(...);
  final attachmentIndex = <Map<String, dynamic>>[];
  final binaries = <AttachmentBinary>[];
  for (final meta in attachmentMetas) {
    final bytes = await _attachments.readBytes(meta.relativePath);
    if (bytes == null) continue;  // 跳过孤儿附件
    attachmentIndex.add({
      'id': meta.id,
      'relativePath': meta.relativePath,
      'mime': meta.mime,
      'size': bytes.length,
      'sha256': sha256Hex(bytes),
    });
    binaries.add(AttachmentBinary(id: meta.id, bytes: bytes));
  }

  final document = BackupDocument(
    ...,
    payload: {
      ...,
      'attachments': attachmentMetas.map(_attachmentToJson).toList(),
    },
    attachmentIndex: attachmentIndex,
    attachmentBinaries: binaries,   // 新增字段
  );
  return document;
}
```

`BackupDocument` 增加：

```dart
class BackupDocument {
  ...
  final List<Map<String, dynamic>>? attachmentIndex;  // envelope 写出去时序列化为 JSON
  final List<AttachmentBinary>? attachmentBinaries;   // 服务层临时持有，不进 envelope
}

class AttachmentBinary {
  final String id;
  final Uint8List bytes;
}
```

`BackupService.restore()` 流程：

```dart
for (final binary in document.attachmentBinaries ?? const []) {
  await _attachments.writeBytes(
    id: binary.id,
    bytes: binary.bytes,
  );
}
```

### 3.3 文件端口改造

`BackupFilePort` 增加：

```dart
Future<String> writeZipBackup(
  BackupDocument document, {
  required String deviceId,
});
Future<BackupDocument> readZipBackup(String source);
```

实现使用 `archive` Dart 包（zip64 + 流式）。`PluginBackupFilePort` 把数据写入 `<documents>/ledgerly-backup-*.ledgerly.zip`，`InMemoryBackupFilePort` 测试替身保留 zip 字节数组。

### 3.4 附件索引展示

`DataGovernancePage` 顶部 status card 增加附件数量和大小：

```
┌─────────────────────────────────────────┐
│  上次备份                               │
│  3 天前 · 14 个附件 · 23.4 MB          │
└─────────────────────────────────────────┘
```

恢复预览卡片增加一行："N 个附件将一并恢复"（v2 文件）。

### 3.5 国际化

新增 4 个键：

| 键 | zh | en |
|---|---|---|
| `dataGovernanceStatusAttachments` | {n} 个附件 · {size} | {n} attachments · {size} |
| `dataGovernanceRestoreAttachmentsV2` | N 个附件将一并恢复 | {n} attachments will be restored |
| `dataGovernanceRestoreNoAttachmentsV1` | 该备份不含附件二进制 | This backup has no attachment binaries |
| `dataGovernanceAttachmentSizeBytes` | {size} MB | {size} MB |

`backupMetadata` schema 增加可选 `attachmentCount` / `attachmentSizeBytes` 字段。

## 4. 实现清单

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `docs/design/phase-9-attachment-bundling.md` | 新增 | 本文档 |
| 2 | `apps/client/pubspec.yaml` | 修改 | +`archive: ^3.x` |
| 3 | `apps/client/lib/application/backup_service.dart` | 修改 | export/restore 集成附件二进制 |
| 4 | `apps/client/lib/application/backup_metadata_store.dart` | 修改 | metadata 存 attachmentCount / attachmentSizeBytes |
| 5 | `apps/client/lib/data/local_attachment_repository.dart` | 修改 | 增加 readBytes / writeBytes |
| 6 | `apps/client/lib/platform/backup_file_port.dart` | 修改 | writeZipBackup / readZipBackup |
| 7 | `apps/client/lib/presentation/providers.dart` | 修改 | 暴露 attachmentSourceProvider |
| 8 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 修改 | status card 加附件计数；恢复预览加附件说明 |
| 9 | `apps/client/lib/l10n/app_en.arb` | 修改 | +4 键 |
| 10 | `apps/client/lib/l10n/app_zh.arb` | 修改 | +4 键 |
| 11 | `apps/client/test/widget/data_governance_page_test.dart` | 修改 | +3 case（含字节往返） |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 附件 zip 包过大（100MB+） | UI 显示尺寸；提供"不含附件"开关（Phase 9.1） |
| 写 zip 时 OOM | archive 包支持 stream API；分块写 |
| 老用户升级后老备份失效 | schemaVersion 向后兼容；v1 文件仍可读，UI 提示无附件 |
| 附件二进制落盘失败 | restore 包在事务内，失败回滚 |
| 文件名冲突 | zip 内 attachments/ 目录按 id 命名，无冲突 |

## 6. 验收

- [ ] `flutter analyze` 无新增 warning/error；
- [ ] `flutter test test/widget/data_governance_page_test.dart` 通过（含 3 个新 case）；
- [ ] `flutter test` 全量通过；
- [ ] 手动跑通：
  - 导出含附件账本 → `.ledgerly.zip` 文件 → 用 unzip 看到 attachments/ 目录；
  - 恢复同一文件 → 附件缩略图正常显示；
  - 旧 v1 文件 → 仍可读，预览显示"不含附件"。