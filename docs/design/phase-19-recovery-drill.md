# Phase 19 — 备份恢复演练

## 1. 背景与动机

Phase 17 的完整性检查证明备份文件存在、SHA-256 未变且外层容器可以解析，
但没有证明数据真的能恢复到当前版本可用的状态：

- 增量文件虽然容器可读，引用的 base 可能已经缺失或损坏；
- 附件索引虽然存在，对应二进制可能缺失或 SHA-256 不匹配；
- summary 与实际 payload 行数可能不一致；
- 加密备份在未输入密码时只能检查外层结构。

本阶段增加“恢复演练”：只读取最近备份，在内存中完成增量合成或解密，
校验恢复所需的数据约束，不修改当前数据库。

## 2. 目标 / 非目标

### 目标

- **G1**：新增 `BackupService.runRecoveryDrill({String? password})`；
- **G2**：只针对 metadata 指向的最近备份执行；
- **G3**：明文增量必须与当前 base 成功合成；
- **G4**：加密备份必须使用密码解密后继续演练；
- **G5**：校验实体 ID、重复行、summary 行数和附件索引；
- **G6**：校验附件二进制大小与 SHA-256；
- **G7**：演练不写数据库、不删除文件、不修改 metadata；
- **G8**：数据治理页提供入口、密码重试和结果摘要。

### 非目标

- 不执行真实 replace / merge 恢复；
- 不保存或缓存用户密码；
- 不一次演练目录中的所有历史备份；
- 不验证远端同步状态或服务端数据；
- 不修复损坏文件或缺失的增量基础。

## 3. API

```dart
class BackupRecoveryDrillResult {
  final String path;
  final String? backupId;
  final bool encrypted;
  final bool incremental;
  final BackupSummary summary;
  final int bundledAttachmentCount;
  final int attachmentSizeBytes;
}

Future<BackupRecoveryDrillResult> runRecoveryDrill({
  String? password,
});
```

加密备份未提供密码或密码错误时抛出 `BackupPasswordException`。

## 4. 演练流程

```text
metadata.lastBackupPath
  -> readBackup (outer container)
  -> encrypted ? decrypt(password) : identity
  -> incremental ? materialize(base + delta) : full
  -> validate rows + summary + attachment hashes
  -> return recovery summary
```

核心校验：

1. 所有实体行必须包含唯一、非空 `id`；
2. payload 中的无效行会被拒绝；
3. `summary` 的实体数量必须与 payload 一致；
4. 每个附件索引必须有对应二进制；
5. 附件 size 和 SHA-256 必须与二进制匹配。

## 5. UI

备份目录操作区增加“恢复演练”入口：

- 明文备份：直接执行并显示结果摘要；
- 加密备份：打开密码对话框，错误密码沿用现有锁定期；
- 成功：显示账本、流水和附件数量，以及备份路径；
- 失败：提示具体异常，不改变本机数据。

## 6. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_service.dart` | 演练 API、结果模型、严格校验 |
| 2 | `data_governance_page.dart` | 入口、密码对话框、结果对话框 |
| 3 | l10n ARB | 演练状态与结果文案 |
| 4 | `backup_recovery_drill_test.dart` | 明文链、加密、附件异常 |
| 5 | `data_governance_page_test.dart` | 明文/加密 UI 路径 |
| 6 | 文档索引和路线图 | Phase 19 |

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 演练被误认为真实恢复 | 结果明确说明只读且不修改本机数据 |
| 加密备份密码错误被判损坏 | 单独抛出密码异常并保留重试锁定期 |
| 旧增量 base 已缺失仍显示健康 | 演练实际执行 `_materializeIncremental` |
| 恶意附件替换仍显示通过 | 逐附件校验 size 与 SHA-256 |
| 演练意外修改本地数据 | 只调用解析/解密/合成路径，不调用 restore/merge |

## 8. 验收

- [x] 明文增量可以完成恢复演练；
- [x] 演练不改变 metadata 与当前数据库；
- [x] 加密备份无密码/错密码不可演练；
- [x] 正确密码可以完成演练；
- [x] 附件哈希不一致会报告失败；
- [x] UI 支持明文/加密入口和结果展示；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（397/397）。
