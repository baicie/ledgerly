# Phase 12 — 自动备份调度

## 1. 背景与动机

Phase 6–11 让用户能手动导出（含加密）快照，Phase 7 会在超过 14 天时提醒。
但提醒仍要人点「立即备份」。真实情况是：用户几天不打开数据治理页，设备坏了
才发现最近一次快照停在几个月前。

本阶段做 **打开应用时的到期检查**：用户打开开关后，Ledgerly 在启动 / 回到前台
时若已超过设定间隔，就静默写一份本地快照。这与周期入账的 `RecurringScheduler.catchUp`
同一套路，不引入后台常驻进程。

## 2. 目标 / 非目标

### 目标

- **G1**：数据治理页可打开「自动备份」，并选择间隔（1 / 7 / 14 / 30 天，默认 7）；
- **G2**：启动与 `AppLifecycleState.resumed` 时调用 `AutoBackupCoordinator.tick`；
  到期则 `BackupService.exportToFile()`（明文 v2，不含密码）；
- **G3**：从未备份 + 已启用 → 视为到期，立即打一份底稿；
- **G4**：开关与间隔持久化到 SharedPreferences，wipe 本地账本**不**清掉这项偏好；
- **G5**：UI 明确写「自动备份不加密」；敏感账本继续走密码导出；
- **G6**：单测覆盖：关闭 / 未到期 / 到期 / 从未备份；widget 覆盖开关与间隔 chip。

### 非目标

- 不引入 `workmanager` / `background_fetch`（web / 桌面无等价物，且要原生配置）；
- 不做系统通知、不上传云盘、不在后台杀进程后仍导出；
- 不把备份密码写入 Secure Storage 做无人值守加密（丢密码 = 丢数据，自动跑太危险）；
- 不覆盖旧文件名策略（仍用带时间戳的新文件）；
- 不动服务端。

后台真正常驻导出留给以后有明确 Android/iOS 产品需求时再做。

## 3. 设计

### 3.1 调度值对象

```dart
class BackupSchedule {
  const BackupSchedule({
    this.enabled = false,
    this.intervalDays = kBackupAutoDefaultIntervalDays,
  });

  final bool enabled;
  final int intervalDays;

  bool isDue(DateTime? lastBackupAt, DateTime now);
}

const kBackupAutoIntervalDays = [1, 7, 14, 30];
const kBackupAutoDefaultIntervalDays = 7;
```

`isDue`：`lastBackupAt == null` 为到期；否则 `now - lastBackupAt` 的整天数
`>= intervalDays`。

### 3.2 存储

`BackupScheduleStore`（SharedPreferences）：

| key | 含义 |
|---|---|
| `ledgerly.backup.autoEnabled` | bool，默认 false |
| `ledgerly.backup.autoIntervalDays` | int，非法值回落到 7 |

与 `BackupMetadataStore` 分开：wipe 只 reset 上次备份时间，不关自动备份。

### 3.3 Coordinator

```dart
class AutoBackupCoordinator {
  Future<AutoBackupTickResult> tick({DateTime? now});
}
```

跳过原因：`disabled` / `notDue` / `inProgress`。成功则返回写出的 path。
异常吞掉并记在 `result.error`，不让 `FutureProvider` 把启动流程打成 error。

`LedgerlyApp`：`ref.watch(autoBackupTickProvider)`，resume 时 invalidate
（与 `recurringCatchUpProvider` 并列）。

### 3.4 UI

数据治理 → 备份区块，密码加密下方：

```
□ 自动备份
  打开应用时检查；到期则写入本地快照。
  [1天] [7天] [14天] [30天]
  ⚠ 自动备份不加密。敏感账本请继续使用密码导出。
```

打开开关后若已到期，当页立刻 `tick` 一次并刷新状态卡。

## 4. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `docs/design/phase-12-auto-backup.md` | 新增 |
| 2 | `apps/client/lib/application/backup_schedule.dart` | 值对象 + store |
| 3 | `apps/client/lib/application/auto_backup.dart` | Coordinator |
| 4 | `apps/client/lib/presentation/providers.dart` | schedule / tick providers |
| 5 | `apps/client/lib/main.dart` | resume 时 tick |
| 6 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 开关 + 间隔 |
| 7 | l10n arb + gen-l10n | 新键 |
| 8 | `test/application/auto_backup_test.dart` | 到期判定 |
| 9 | `test/widget/data_governance_page_test.dart` | 开关 / chip |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 未打开应用就不会备份 | 文案写明「打开应用时检查」；Phase 7 横幅仍在 |
| 自动快照是明文 | 警示条；加密仍是手动动作 |
| 连续 resume 重复导出 | coordinator 单飞；`lastBackupAt` 成功后立即刷新 |
| 文档目录堆文件 | 本阶段接受；清理策略留给以后 |

## 6. 验收

- [x] `dart analyze` 无新增 warning/error；
- [x] `flutter test test/application/auto_backup_test.dart` 通过；
- [x] `flutter test test/widget/data_governance_page_test.dart` 通过。

## 7. 后续候选

- Phase 13：跨账本 merge 恢复；
- Phase 14：增量 diff 备份；
- 真后台：仅 Android/iOS 再评估 workmanager。
