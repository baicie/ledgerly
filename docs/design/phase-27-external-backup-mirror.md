# Phase 27 — 外部备份目录与镜像

## 1. 背景与动机

Phase 25 保证单个备份文件原子写入，但备份仍默认只存在于应用文档目录。
设备丢失、应用被卸载或目录被系统清理时，单点风险仍然存在。

本阶段允许用户选择外部目录，并在本地备份成功后将文件镜像过去。

## 2. 目标 / 非目标

### 目标

- **G1**：用户可选择并持久化一个外部备份目录；
- **G2**：新备份本地成功后，自动镜像到外部目录；
- **G3**：选择目录时批量镜像已有 catalog 文件；
- **G4**：外部写入使用 `AtomicFileWriter`；
- **G5**：镜像失败不改变本地备份成功结果；
- **G6**：catalog 记录 mirrored / failed 状态；
- **G7**：健康中心提示外部目录不可用或最近镜像失败；
- **G8**：数据治理页支持选择、清除和立即镜像。

### 非目标

- 不删除外部目录中的历史文件；
- 不提供双向同步或外部目录扫描；
- 不读取外部目录内容做恢复；
- 不把目录路径加入治理报告；
- 不保证移动端平台都提供目录选择；
- 不自动创建用户未选择的任意目录。

## 3. 数据模型

```dart
class BackupMirrorStore {
  Future<String?> read();
  Future<void> save(String directory);
  Future<void> clear();
}

enum BackupArtifactMirrorStatus { mirrored, failed }

class BackupArtifact {
  final BackupArtifactMirrorStatus? mirrorStatus;
  final String? mirrorPath;
}
```

## 4. 镜像流程

```text
backup local atomic write
  -> metadata/catalog local success
  -> external directory configured?
       no  -> catalog mirrorStatus = null
       yes -> atomic copy to external directory
                success -> mirrored + mirrorPath
                failure -> failed
```

镜像失败只影响 catalog 状态，不改变本地备份结果。

### 批量镜像

选择新目录或用户点击“立即镜像”时：

1. 读取 catalog；
2. 对每个本地文件执行外部 atomic copy；
3. 逐项更新 mirrored / failed；
4. 返回成功和失败数量。

批量镜像保证 full 与依赖它的 incremental 可以进入同一外部目录。

## 5. File Port

```dart
Future<String?> pickBackupDirectory();
Future<String> mirrorBackup(String source, String directory);
Future<bool> isBackupDirectoryAvailable(String directory);
```

平台实现使用 `FilePicker.getDirectoryPath()`，复制时读取本地文件 bytes，
通过 `AtomicFileWriter` 写目标目录中的同名文件。

## 6. UI

备份设置区增加：

```text
外部备份目录
[选择目录] [立即镜像]
```

已配置时展示目录路径并提供移除按钮。目录项标签增加：

- 已镜像；
- 镜像失败。

健康中心：

- 外部目录配置但不可访问 → warning；
- 最近备份镜像失败 → warning；
- 推荐操作打开目录选择。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_mirror_store.dart` | 目录偏好持久化 |
| 2 | `backup_catalog_store.dart` | mirrorStatus / mirrorPath |
| 3 | `backup_service.dart` | 自动镜像、批量镜像 |
| 4 | `backup_file_port.dart` | 目录选择、原子镜像、可用性 |
| 5 | `backup_health.dart` | 镜像失败/目录不可用 |
| 6 | `data_governance_page.dart` | 目录设置、立即镜像、状态 |
| 7 | l10n ARB | 目录、结果和健康文案 |
| 8 | 镜像与文件端口测试 | 成功/失败/批量/不可用 |
| 9 | 文档索引和路线图 | Phase 27 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 外部写入失败影响本地备份 | 本地先完成，镜像独立 try/catch |
| 部分复制产生损坏镜像 | 复用 AtomicFileWriter |
| 选择目录后只有最新 delta | 选择时批量镜像全部 catalog |
| 权限撤销导致误导 | 健康检查目录可用性并标记失败 |
| 用户误删外部目录 | 清除设置只停止后续镜像，不操作文件 |
| 外部路径进入报告 | 治理报告白名单不包含 mirrorPath |

## 9. 验收

- [x] 外部目录可持久化和清除；
- [x] 新备份成功自动镜像；
- [x] 镜像失败不影响本地备份和 metadata；
- [x] 选择目录可批量镜像已有 catalog；
- [x] catalog 显示 mirrored / failed；
- [x] 健康中心报告目录不可用或镜像失败；
- [x] 平台镜像使用原子写入；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（434/434）。
