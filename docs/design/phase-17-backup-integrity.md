# Phase 17 — 备份完整性检查

## 1. 背景与动机

Phase 15 已记录备份目录，Phase 16 已能生成独立全量文件，但目录中的文件仍可能：

- 被文件管理器误删；
- 被同步工具截断或覆盖；
- 因磁盘/传输问题损坏；
- 被恶意或意外修改。

仅显示“有几份备份、占多少 MB”不能证明这些文件仍可读取。本阶段增加显式
完整性检查：验证文件存在、大小未变、SHA-256 匹配，并能被备份解析器打开。

## 2. 目标 / 非目标

### 目标

- **G1**：`BackupArtifact` 增加可选 `sha256`；
- **G2**：新写入的备份在登记目录时计算 SHA-256；
- **G3**：旧 catalog 记录没有 hash 时，首次检查自动补算并视为 healthy；
- **G4**：检查结果区分 healthy / missing / corrupted；
- **G5**：corrupted 包括 hash 不匹配和备份容器无法解析；
- **G6**：检查不修改、不删除任何备份文件；
- **G7**：数据治理页提供“检查完整性”，显示总数和异常明细。

### 非目标

- 不自动删除损坏文件；
- 不尝试修复损坏备份；
- 不使用远端 checksum 服务；
- 不验证加密备份的密码或内层 payload，只验证外层 `enc.zip` 可解析；
- 不校验备份所依赖 base 的逻辑链；该项仍由恢复/便携化流程负责。

## 3. 数据模型

```dart
class BackupArtifact {
  final String? sha256;
}

enum BackupVerificationStatus { healthy, missing, corrupted }

class BackupVerificationEntry {
  final BackupArtifact artifact;
  final BackupVerificationStatus status;
  final String? actualSha256;
  final String? error;
}

class BackupVerificationReport {
  final List<BackupVerificationEntry> entries;
  int get healthyCount;
  int get missingCount;
  int get corruptedCount;
}
```

## 4. 检查流程

对每个 catalog artifact：

1. 读取文件 SHA-256；`null` 表示文件缺失；
2. 若 catalog 没有预期 hash：
   - 使用当前文件 hash 补写 catalog；
   - 继续做结构解析；
3. 当前 hash 与预期 hash 不同 → `corrupted`；
4. 调用 `BackupFilePort.readBackup(path)` 做容器级解析；
   - v3 加密文件只解析外层 envelope；
   - v2/v3 增量文件解析 manifest/data；
5. 解析异常 → `corrupted`；
6. 其它情况 → `healthy`。

文件缺失不会从 catalog 删除，方便用户看到并决定清理。

## 5. File Port

```dart
Future<String?> fileSha256(String source);
```

- 文件不存在返回 `null`；
- 大文件使用流式 SHA-256，避免整文件读入内存；
- `InMemoryBackupFilePort` 对 `rawFiles` 字节直接计算。

## 6. UI

备份目录卡的按钮组增加：

```text
[检查完整性] [清理旧备份]
```

检查完成后：

- 全部健康：显示“已验证 N 份备份”；
- 有异常：打开明细对话框，列出缺失/损坏文件路径与原因。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_catalog_store.dart` | sha256 字段、copyWith/update |
| 2 | `backup_service.dart` | verify API、catalog 写入 hash |
| 3 | `backup_file_port.dart` | fileSha256 |
| 4 | `data_governance_page.dart` | 检查入口、结果对话框 |
| 5 | l10n ARB | 状态与错误文案 |
| 6 | `backup_integrity_test.dart` | healthy/missing/corrupted/legacy |
| 7 | widget test | 检查按钮和异常明细 |
| 8 | 文档索引和路线图 | Phase 17 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 旧记录没有 hash 被误报损坏 | 首次补算后视为 healthy |
| 大文件哈希阻塞 UI | File Port 流式计算，调用由 busy 状态包裹 |
| 加密备份无法无密码解析内层 | 只做外层容器解析 |
| 用户误以为检查会修复文件 | UI 只报告，不删除、不修改文件 |
| catalog 与服务实例 hash 不一致 | 检查结果同步 upsert catalog |

## 9. 验收

- [x] 新写入备份的 catalog 含 SHA-256；
- [x] 正常 full / incremental / encrypted 均判 healthy；
- [x] 缺失文件判 missing；
- [x] 字节损坏或结构损坏判 corrupted；
- [x] 旧记录无 hash 时自动补算；
- [x] UI 显示检查结果和异常路径；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（390/390）。
