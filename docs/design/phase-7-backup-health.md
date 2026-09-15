# Phase 7 — 备份健康追踪 & 提醒 (Backup Health Tracking)

## 1. 背景与动机

Phase 6 落地了"导出 / 恢复 / 清空"三件套，但用户**完全不知道距离上次备份多久了**：

- `DataGovernancePage._lastBackupPath` 只在内存中存，**重启即丢**；
- 没有"距上次备份 X 天"的可见信号；
- 没有"已经很久没备份"的温和提醒。

真实场景：
- 用户半年前做过一次备份，之后从未再备份；某天设备损坏才后悔；
- 老用户不打开这一页，根本不知道自己有"备份"这件事；
- 新用户从未导出过，没有任何提示引导他们做第一次备份。

数据治理的核心是"让用户拿回对自己数据的掌控感"，而**让用户随时知道"我是不是最近做过备份"** 是这个掌控感的关键一环。

## 2. 目标 / 非目标

### 目标
- **G1**：每次成功导出备份后，把 `lastBackupAt` 时间戳持久化到 SharedPreferences (`ledgerly.backup.lastAt`)；
- **G2**：`DataGovernancePage` 顶部增加"上次备份"小卡片，展示相对时间（"3 天前"/"从未备份"）；
- **G3**：距离上次备份 >14 天时，在页面顶部插入一个**非阻塞**提醒横幅："距离上次备份已 X 天" + "立即备份"按钮；
- **G4**：清空本地数据时重置 `lastBackupAt`，避免显示陈旧时间；
- **G5**：所有 widget 测试覆盖：从未备份 / 近期备份 / 过期备份 / 清空后重置。

### 非目标
- 不做云端自动备份（属于同步 / 商业化范畴）；
- 不做系统级通知（Notification Service）；
- 不做强制备份拦截；
- 不做"备份过期则禁止打开某些功能"；
- 不增加新依赖。

## 3. 设计

### 3.1 数据模型

新增 `apps/client/lib/application/backup_metadata_store.dart`：

```dart
class BackupMetadata {
  const BackupMetadata({this.lastBackupAt, this.lastBackupPath});
  final DateTime? lastBackupAt;
  final String? lastBackupPath;

  bool get hasBackup => lastBackupAt != null;
  Duration? get ageFrom(DateTime now) =>
      lastBackupAt == null ? null : now.difference(lastBackupAt!);

  bool get isStale {
    if (lastBackupAt == null) return true;
    return DateTime.now().difference(lastBackupAt!).inDays >= 14;
  }
}

class BackupMetadataStore {
  BackupMetadataStore({SharedPreferences? prefs}) : _prefs = prefs;
  static const _kLastAt = 'ledgerly.backup.lastAt';
  static const _kLastPath = 'ledgerly.backup.lastPath';

  Future<BackupMetadata> read();
  Future<void> record({required String path, required DateTime at});
  Future<void> reset();
}
```

设计要点：
- 暴露纯函数式 `BackupMetadata` 值对象，UI 层拿到的是快照，不直接持有 store；
- `ageFrom(now)` 接受时间入参，方便测试注入；
- `isStale` 用 14 天作为阈值（藏在常量里）；
- `reset()` 用于 wipe 后清掉，避免 UI 误以为还有备份。

### 3.2 BackupService 接入

`BackupService.exportToFile()` 在成功写入后调用 `BackupMetadataStore.record(...)`：

```dart
Future<String> exportToFile() async {
  ...
  final path = await _files.writeBackup(document, deviceId: deviceId);
  await _metadata.record(path: path, at: DateTime.now().toUtc());
  return path;
}
```

`BackupService.wipeLocalData()` 末尾调用 `BackupMetadataStore.reset()`：

```dart
await _wipeLocalData();
await _metadata.reset();   // 新增
```

`BackupService` 构造函数新增 `metadata: BackupMetadataStore` 参数（注入 `SharedPreferences`）。

### 3.3 UI 改动

`DataGovernancePage` 顶部 `LedgerlyPageHeader` 下方新增 `_BackupStatusCard`：

```
┌─────────────────────────────────────────┐
│  上次备份                               │
│  3 天前 · /path/.../ledgerly.json       │
└─────────────────────────────────────────┘
```

如果 `lastBackupAt == null`，显示"从未备份"占位文案。

如果 `isStale == true`，页面顶部插入一个 `_StaleBanner`：

```
┌─────────────────────────────────────────┐
│ ⚠ 距离上次备份已 18 天。                 │
│   [立即备份]                             │
└─────────────────────────────────────────┘
```

横幅要点：
- 颜色用 `colorScheme.tertiaryContainer` + `onTertiaryContainer`（温和提示，不是错误）；
- 点击"立即备份"调用 `_exportBackup()`；
- 横幅**不阻塞**操作，用户仍可以正常浏览 / 恢复 / 清空；
- 横幅 key: `data-governance-stale-banner`，方便测试断言。

### 3.4 国际化

新增 5 个键：

| 键 | zh | en |
|---|---|---|
| `dataGovernanceStatusTitle` | 上次备份 | Last backup |
| `dataGovernanceStatusNever` | 从未备份 | Never backed up |
| `dataGovernanceStatusRecent` | {ago} 之前 | {ago} ago |
| `dataGovernanceStaleBannerTitle` | 距离上次备份已 {days} 天 | Last backup is {days} days old |
| `dataGovernanceStaleBannerAction` | 立即备份 | Back up now |

`dataGovernanceStatusRecent({ago})` 接收本地化的相对时间字符串（例如"3 天"）。

### 3.5 Provider 注入

`backupServiceProvider` 改造：

```dart
final backupServiceProvider = Provider<BackupService>((ref) {
  final db = ref.watch(databaseProvider);
  final recurring = LocalRecurringRepository(db);
  ...
  final metadata = BackupMetadataStore();   // 默认读 SharedPreferences
  return BackupService(..., metadata: metadata);
});
```

测试用 `overrideWithValue` 注入内存版 store。

## 4. 实现清单

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `docs/design/phase-7-backup-health.md` | 新增 | 本文档 |
| 2 | `apps/client/lib/application/backup_metadata_store.dart` | 新增 | SharedPreferences 封装 + BackupMetadata 值对象 |
| 3 | `apps/client/lib/application/backup_service.dart` | 修改 | 注入 metadata store，export/wipe 时调用 |
| 4 | `apps/client/lib/presentation/providers.dart` | 修改 | backupServiceProvider 装配 metadata |
| 5 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 修改 | 增加 status card + stale banner |
| 6 | `apps/client/lib/l10n/app_en.arb` | 修改 | +5 键 |
| 7 | `apps/client/lib/l10n/app_zh.arb` | 修改 | +5 键 |
| 8 | `apps/client/test/widget/data_governance_page_test.dart` | 修改 | 增加 3 个 case |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 时区错乱（用户改时区后相对时间不准） | 持久化 UTC，渲染时按本地时区格式化 |
| SharedPreferences 损坏导致读不到 | `read()` 捕获异常返回空 metadata |
| 横幅被频繁弹出（每次打开页面都看到） | 用 SharedPreferences 持久化"上次看到横幅"时间，24 小时内不再显示（v2 实现） |
| 测试需要注入"当前时间" | BackupMetadata 接受 `now` 参数；store 单测覆盖正常 / 异常路径 |

## 6. 验收

- [ ] `flutter analyze` 无新增 warning/error；
- [ ] `flutter test test/widget/data_governance_page_test.dart` 通过（含 3 个新 case）；
- [ ] `flutter test` 全量通过；
- [ ] 手动跑通：
  - 新装首次打开数据治理页 → 显示"从未备份"，无横幅；
  - 导出成功 → 顶部卡片显示"刚刚"；
  - 修改 SharedPreferences 把 lastAt 改到 18 天前 → 顶部出现横幅；
  - 清空本地数据 → 回到"从未备份"。