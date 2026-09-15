# Phase 22 — 加密自动备份

## 1. 背景与动机

Phase 12 的自动备份写在应用打开或回到前台时执行，但始终生成明文增量。
当自动备份落到设备目录并被同步工具收集时，敏感账本会以明文存在。

本阶段增加可选的加密自动备份模式：密码保存在系统安全存储中，调度到期时
生成独立加密全量，不进入明文增量 base 链。

## 2. 目标 / 非目标

### 目标

- **G1**：`BackupSchedule` 增加 `encrypted` 偏好；
- **G2**：密码通过系统安全存储保存，不写入 SharedPreferences；
- **G3**：自动备份启用加密后始终生成独立加密全量；
- **G4**：加密自动备份不更新增量 base；
- **G5**：密码缺失时跳过，不降级生成明文；
- **G6**：安全存储不可用时跳过并返回明确原因；
- **G7**：关闭加密模式时清除保存的密码；
- **G8**：数据治理页提供加密开关、设置密码和状态说明；
- **G9**：自动备份失败不得阻塞应用启动。

### 非目标

- 不提供密码找回；
- 不把密码写入日志、备份文件或 SharedPreferences；
- 不自动切换旧自动备份的加密状态；
- 不将加密自动备份作为增量 base；
- 不在后台常驻或后台 isolate 中运行；
- 不批量迁移已有明文自动备份。

## 3. 数据模型

```dart
class BackupSchedule {
  final bool enabled;
  final int intervalDays;
  final bool encrypted;
}
```

密码存储：

```dart
abstract interface class BackupAutoPasswordStore {
  Future<String?> read();
  Future<void> write(String password);
  Future<void> clear();
}
```

平台实现使用 `FlutterSecureStorage`，key 为
`ledgerly.backup.autoPassword.v1`。

## 4. 调度流程

```text
tick()
  -> schedule disabled / not due / in progress
  -> encrypted?
       -> read secure password
       -> missing password = skip
       -> secure storage error = skip
       -> export encrypted full
     : export plaintext incremental
```

加密辅助原因：

```dart
enum AutoBackupSkipReason {
  disabled,
  notDue,
  inProgress,
  encryptedPasswordMissing,
  encryptedPasswordUnavailable,
}
```

## 5. 文件语义

明文自动备份继续：

- `automatic + incremental/full`；
- 可成为后续增量 base。

加密自动备份：

- `automatic + encrypted`；
- 每次生成独立 full；
- 不更新 `baseBackupId/baseBackupPath`；
- 恢复时需要密码。

## 6. UI

自动备份区域增加“加密自动备份”开关：

- 开启时弹出新密码 + 确认；
- 密码校验至少 8 位且两次一致；
- 保存密码后才写入 schedule；
- 关闭时先关闭加密偏好，再清除安全存储密码；
- 缺少密码或安全存储不可用时显示提示，不生成明文文件。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_schedule.dart` | encrypted 偏好持久化 |
| 2 | `backup_auto_password_store.dart` | 安全存储与内存测试实现 |
| 3 | `auto_backup.dart` | 加密分支、skip reasons |
| 4 | `providers.dart` | 自动密码 store provider |
| 5 | `data_governance_page.dart` | 开关、设置密码、状态提示 |
| 6 | l10n ARB | 加密自动备份文案 |
| 7 | `auto_backup_test.dart` | 缺密码/存储异常/加密全量 |
| 8 | `data_governance_page_test.dart` | 设置和清除密码 |
| 9 | 文档索引和路线图 | Phase 22 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 密码缺失时静默生成明文 | 返回 missingPassword 并直接跳过 |
| 安全存储异常阻塞启动 | coordinator 吞掉异常并返回 skip reason |
| 加密文件误当增量 base | 加密分支始终 `incremental: false` |
| 密码写入普通偏好 | 只使用 FlutterSecureStorage |
| 关闭后密码残留 | 关闭加密模式时调用 clear |
| 自动备份失败影响主流程 | 继续返回 `AutoBackupTickResult.failed` |

## 9. 验收

- [x] schedule 持久化 encrypted；
- [x] 密码保存在安全存储并支持清除；
- [x] 加密模式生成独立加密全量；
- [x] 加密模式不更新增量 base；
- [x] 缺少密码时跳过且不写明文；
- [x] 安全存储异常时安全跳过；
- [x] UI 支持设置密码、开关和状态提示；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（411/411）。
