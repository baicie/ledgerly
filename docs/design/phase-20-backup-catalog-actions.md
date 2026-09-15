# Phase 20 — 备份目录逐项操作

## 1. 背景与动机

Phase 15 已维护本机备份目录，Phase 17 可检查完整目录，Phase 19 可演练最近
备份。但目录此前仍只是数量汇总：

- 用户看不到每份备份的类型、来源、时间和路径；
- 历史增量只能依赖 metadata 当前 base，切换 base 后无法直接恢复；
- 加密目录项不能单独解锁进入恢复预览；
- 只能批量清理，不能安全删除一份明确选择的历史文件。

本阶段把目录从统计信息升级为可操作的文件列表。

## 2. 目标 / 非目标

### 目标

- **G1**：`BackupArtifact` 记录增量文件的 `baseBackupId`；
- **G2**：目录展示完整、增量、加密和来源类型；
- **G3**：历史增量按自身 `baseBackupId` 在目录中查找 base；
- **G4**：任意目录项支持独立恢复演练；
- **G5**：明文目录项直接加载，加密目录项密码解锁后加载恢复预览；
- **G6**：目录项支持分享和确认式单独删除；
- **G7**：当前 base、最近备份及被增量依赖的文件不能删除；
- **G8**：旧 catalog 记录在读取、校验或删除检查时补全 base ID。

### 非目标

- 不修改备份 schema；
- 不把目录项复制到其他目录；
- 不自动修复缺失的 base；
- 不修改 Phase 15 的批量保留策略；
- 不允许删除当前恢复链所需的文件；
- 不保存加密目录项的密码。

## 3. 数据模型

```dart
class BackupArtifact {
  final String? baseBackupId;
}
```

该字段仅对增量文件有值，用于：

- 历史增量恢复到正确 base；
- 判断删除某个 full 是否会破坏其他增量；
- 兼容缺失该字段的旧 catalog 记录。

## 4. API

```dart
Future<BackupDocument> readCatalogBackup(
  BackupArtifact artifact,
);

Future<BackupDocument> unlockCatalogBackup(
  BackupArtifact artifact, {
  required String password,
});

Future<BackupRecoveryDrillResult> runCatalogRecoveryDrill(
  BackupArtifact artifact, {
  String? password,
});

Future<int> deleteCatalogArtifact(
  BackupArtifact artifact,
);
```

### 历史 base 解析

1. 先尝试 metadata 当前 base；
2. 再从 catalog 查找匹配 `backupId` 的 base；
3. base 必须为未加密 full；
4. 找不到或不可读时返回明确错误，不回退到当前数据库。

### 删除保护

以下文件禁止单独删除：

- `metadata.lastBackupPath`；
- `metadata.baseBackupPath`；
- 任意增量文件的 `baseBackupId` 指向的文件；
- 旧增量未记录 base ID 且无法读取、无法排除依赖的基础文件。

## 5. UI

备份目录汇总下方增加可展开文件列表。每项显示：

- full / incremental / encrypted；
- manual / automatic / safety；
- 创建时间、大小和路径；
- `当前基础`、`最近备份` 标识。

每项菜单提供：

```text
分享
恢复演练
加载到恢复预览
删除此备份
```

当前 base、latest 和存在依赖的文件禁用删除。加密备份在演练或恢复前弹出
密码对话框，并复用 Phase 10/19 的错误密码锁定行为。

## 6. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_catalog_store.dart` | baseBackupId 持久化与兼容读取 |
| 2 | `backup_service.dart` | 历史解析、解锁、演练、删除保护 |
| 3 | `data_governance_page.dart` | 目录列表、菜单、恢复/删除交互 |
| 4 | l10n ARB | 类型、来源、操作与错误文案 |
| 5 | `backup_catalog_test.dart` | 历史 base、加密解锁、删除保护 |
| 6 | `data_governance_page_test.dart` | 列表、演练、恢复和删除 |
| 7 | 文档索引和路线图 | Phase 20 |

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 历史增量误用当前 base | catalog 按记录 ID 解析 base |
| 删除 base 破坏增量 | 记录并检查 baseBackupId |
| 旧记录没有 base ID | 读取/校验时回填 |
| 加密目录项直接进入预览 | 先解锁并合成为可恢复快照 |
| 用户误删唯一恢复链 | 当前 base/latest/依赖文件禁止删除 |
| 大目录撑高页面 | 列表收纳在展开区中，按时间排序 |

## 8. 验收

- [x] catalog 记录并读取增量 baseBackupId；
- [x] metadata 切换 base 后仍可恢复历史增量；
- [x] 加密目录项可单文件解锁；
- [x] 目录项可独立演练、加载恢复预览、分享和删除；
- [x] 当前 base、latest 和依赖文件删除被阻止；
- [x] 旧 catalog 缺失 base ID 时可回填；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（403/403）。
