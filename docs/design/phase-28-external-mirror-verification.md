# Phase 28 — 外部镜像校验与恢复入口

## 1. 背景与动机

Phase 27 可以自动镜像新备份，但 catalog 中的“已镜像”状态只代表当时的
镜像操作成功。外部目录之后可能发生：

- 文件被删除；
- 文件被同步工具截断或覆盖；
- 磁盘故障导致字节损坏；
- 用户手动放入未登记的备份文件。

本阶段增加外部目录一致性校验，并允许把外部额外备份导入本地 catalog。

## 2. 目标 / 非目标

### 目标

- **G1**：扫描配置的外部备份目录；
- **G2**：逐项验证外部副本存在、大小和 SHA-256；
- **G3**：识别外部目录中未登记的备份文件；
- **G4**：输出 healthy / missing / corrupted / extra；
- **G5**：外部异常进入备份策略健康中心；
- **G6**：允许把 extra 文件原子复制到本机并登记 catalog；
- **G7**：导入失败清理本机临时副本；
- **G8**：数据治理页提供检查镜像、异常明细和导入操作。

### 非目标

- 不删除外部异常文件；
- 不自动覆盖损坏镜像；
- 不自动导入所有 extra 文件；
- 不读取或迁移外部目录中的附件；
- 不跨设备同步 catalog；
- 不校验远端云盘状态；
- 不把外部路径写入治理报告。

## 3. 数据模型

```dart
enum BackupMirrorVerificationStatus {
  healthy,
  missing,
  corrupted,
  extra,
}

class BackupMirrorVerificationEntry {
  final String externalPath;
  final BackupMirrorVerificationStatus status;
  final BackupArtifact? artifact;
  final String? expectedSha256;
  final String? actualSha256;
  final int? expectedSizeBytes;
  final int? actualSizeBytes;
}
```

## 4. 校验流程

```text
configured external directory
  -> read catalog mirror records
  -> for each mirrored artifact:
       file exists?
       size matches?
       SHA-256 matches?
  -> list external backup-looking files
  -> files not referenced by catalog = extra
```

目录不存在时校验失败并由健康中心报告 `externalDirectoryUnavailable`。

## 5. 导入流程

```text
external extra file
  -> atomic copy into app-owned storage
  -> parse backup container
  -> create manual catalog artifact
  -> mirrorStatus = mirrored
  -> mirrorPath = external source
```

如果读取或 catalog 登记失败，则删除刚导入的本机文件。

## 6. 健康中心

新增 warning：

- `externalMirrorMissing`；
- `externalMirrorCorrupted`；
- `externalMirrorExtra`。

推荐操作统一为检查/配置外部目录。

## 7. UI

外部备份目录卡增加“检查镜像”：

- 全部正常：显示健康数量；
- 有异常：打开对话框，列出路径和状态；
- extra 项提供“导入本机”；
- 导入成功后刷新 catalog 和健康状态。

## 8. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_mirror_verification.dart` | 校验结果模型 |
| 2 | `backup_service.dart` | 校验与导入 API |
| 3 | `backup_file_port.dart` | 扫描与导入外部文件 |
| 4 | `backup_health.dart` | 外部镜像异常项 |
| 5 | `data_governance_page.dart` | 检查对话框和导入 |
| 6 | l10n ARB | 状态、错误与导入文案 |
| 7 | `backup_mirror_test.dart` | 健康/缺失/损坏/extra/导入 |
| 8 | `backup_file_port_test.dart` | 扫描与原子导入 |
| 9 | 文档索引和路线图 | Phase 28 |

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 大文件校验阻塞 | 使用流式 SHA-256，页面显示 busy |
| 同步工具仍在上传 | 不删除、不覆盖，只报告和导入 |
| extra 文件实际损坏 | 导入前解析容器，失败清理 |
| 导入重复 backupId | catalog 按 backupId 去重 |
| 外部路径泄露 | 治理报告不包含 mirrorPath |
| 外部目录不可用 | 先做 availability 检查，再扫描 |

## 10. 验收

- [x] 健康镜像按 SHA-256 验证；
- [x] 缺失、损坏和 extra 可区分；
- [x] extra 文件可导入本机 catalog；
- [x] 导入失败清理本机副本；
- [x] 健康中心报告外部镜像异常；
- [x] UI 展示明细并支持导入；
- [x] 文件端口原子扫描/导入；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（437/437）。
