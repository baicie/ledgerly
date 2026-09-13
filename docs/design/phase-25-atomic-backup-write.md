# Phase 25 — 原子备份写入与故障注入

## 1. 背景与动机

此前平台备份通过 `File.writeAsBytes()` 直接覆盖目标文件。磁盘写满、权限
错误、进程中断或重命名式存储故障时，可能留下：

- 截断但不完整的备份文件；
- 被部分覆盖的旧备份；
- metadata 已更新但文件不可读；
- catalog 已登记但文件未完整落盘。

本阶段将备份写入改为同目录临时文件 + flush + 原子 rename。

## 2. 目标 / 非目标

### 目标

- **G1**：新增可注入的 `AtomicFileWriter`；
- **G2**：先写同目录临时文件，再 rename 到目标路径；
- **G3**：写入或 rename 失败时保留原目标文件；
- **G4**：失败后尽量清理残留临时文件；
- **G5**：普通导出、加密导出、增量导出和安全备份统一走原子写入；
- **G6**：安全备份文件名加入 backupId 后缀，避免同分钟碰撞；
- **G7**：写入失败不得更新 metadata 或 catalog；
- **G8**：测试可模拟磁盘写满和 rename 失败。

### 非目标

- 不提供跨进程文件锁；
- 不保证掉电后目录项持久化，只使用 `flush: true`；
- 不改变备份 zip/envelope 格式；
- 不提供损坏文件自动修复；
- 不改变 UI 流程；
- 不把附件 store 纳入本阶段。

## 3. API

```dart
typedef AtomicBytesWriter = Future<void> Function(
  File file,
  List<int> bytes,
);

typedef AtomicFileMover = Future<File> Function(
  File file,
  String newPath,
);

class AtomicFileWriter {
  Future<void> write(File target, List<int> bytes);
}
```

默认实现：

1. 创建目标父目录；
2. 生成同目录临时路径；
3. `writeAsBytes(..., flush: true)`；
4. `File.rename(target.path)`；
5. 任意步骤失败时删除临时文件并重新抛出原异常。

## 4. 平台接入

`PluginBackupFilePort` 接受可选 `AtomicFileWriter`，以下写入统一使用：

- 明文 full `.ledgerly.zip`；
- incremental `.ledgerly.inc.zip`；
- encrypted `.ledgerly.enc.zip`；
- pre-restore safety `.ledgerly.zip`。

安全备份：

```text
ledgerly-pre-restore-YYYY-MM-DD_HHmm-<backupId8>.ledgerly.zip
```

## 5. 失败语义

```text
write backup
  -> temporary file complete?
       no  -> delete temp, target unchanged
       yes -> rename succeeds?
                no  -> delete temp, target unchanged
                yes -> return final path
```

`BackupService` 只有在 `writeBackup()` 成功后才会记录 metadata/catalog，
因此平台写入失败不会产生无效登记。

## 6. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `atomic_file_writer.dart` | 原子写入器与注入点 |
| 2 | `backup_file_port.dart` | 所有平台写入改用原子写入 |
| 3 | `backup_file_port_test.dart` | 部分写入、rename 失败、成功替换 |
| 4 | `backup_atomic_write_test.dart` | 服务失败不污染 metadata/catalog |
| 5 | 文档索引和路线图 | Phase 25 |

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 临时文件残留 | catch 中 best-effort 删除 |
| 失败覆盖旧备份 | 完整写入成功前不改目标路径 |
| 失败仍登记 catalog | 服务只在写成功后记录 |
| 同分钟安全备份碰撞 | 文件名增加 backupId 后缀 |
| 注入点影响生产路径 | 默认 writer/mover 使用 Dart 标准文件 API |
| 异常被清理错误覆盖 | 清理异常被吞掉，保留原写入异常 |

## 8. 验收

- [x] 成功写入通过临时文件完成；
- [x] 部分写入失败保留原文件；
- [x] rename 失败保留原文件；
- [x] 失败清理临时文件；
- [x] 平台导出和恢复前安全备份统一原子写入；
- [x] 写入失败不更新 metadata 或 catalog；
- [x] 文件名碰撞得到规避；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（425/425）。
