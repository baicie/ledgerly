# Phase 6 — 数据治理 (Backup / Restore / Wipe)

## 1. 背景与动机

Ledgerly 客户端是 local-first 架构,所有账本数据存在设备本地 SQLite。同步是可选的云备份。但当前 **用户对"我的数据是否安全"完全没有控制权**：

| 已有 | 缺失 |
|---|---|
| CSV 流水导出 (`ExportPage`) | 全应用快照 (账本/分类/账户/预算/周期/规则/设置) |
| CSV 账单导入 (`ImportPage`) | 全应用还原 (跨设备恢复、设备更换、误删救命) |
| — | "清空本地数据"入口 (误操作清理、隐私退出) |
| — | 自动备份前置 (做任何危险操作前的兜底) |

用户的真实痛点：
1. **换手机**：没法把账本迁到新机，只能从头再来；
2. **家人共用**：家庭成员看不到同一份账本；
3. **卸载前**：想留个备份文件在网盘里；
4. **试用期/共享设备**：临时退出时要把本地数据清干净。

CSV 导出/导入解决不了以上任何一条 — 它只覆盖交易行，不覆盖账本骨架、分类树、预算、周期规则、附件元数据、商家规则、自动记账开关。

本阶段做 **v1：Backup / Restore / Wipe** 三件套，覆盖最常见的"数据恐慌"场景。

## 2. 目标 / 非目标

### 目标
- **G1**：用户在 Settings → 数据治理 一键导出全应用快照为单一 `.ledgerly.json` 文件（含 schema 版本号 + 导出时间）；
- **G2**：从备份文件还原，**replace 模式**（清空当前数据后整体替换），强制先自动备份当前数据再确认；
- **G3**：用户在数据治理页可一键"清空本地数据"，要求键入 `DELETE` 二次确认；
- **G4**：以上三种操作有 widget 测试覆盖 happy path + 二次确认弹窗。

### 非目标
- 不做增量合并（merge 模式留给 v2）；
- 不做加密备份（password-protected zip 留给 v2）；
- 不做云端定时自动备份（属于同步/商业化范畴）；
- 不动 Rust 后端的备份接口（只动客户端本地数据）；
- 不改 CSV 导出/导入（保留为轻量分享入口）；
- 不实现增量备份 / 差异同步（与现有 sync 引擎职责冲突）；
- 不做附件二进制（仅备份元数据，文件实体需手动复制）。

## 3. 设计

### 3.1 备份文件 Schema

文件扩展名：`.ledgerly.json`（可读、可 diff、未来易迁移）。
顶层结构：

```json
{
  "kind": "ledgerly-backup",
  "schemaVersion": 1,
  "exportedAt": "2026-09-13T10:00:00.000Z",
  "deviceId": "<原 deviceId>",
  "summary": {
    "books": 1,
    "accounts": 12,
    "categories": 24,
    "transactions": 348,
    "entries": 712,
    "recurringRules": 5,
    "budgets": 6,
    "attachments": 14,
    "merchantRules": 3,
    "fxRates": 4
  },
  "data": {
    "books": [Book JSON...],
    "accounts": [...],
    "categories": [...],
    "transactions": [...],
    "transactionEntries": [...],
    "recurringRules": [...],
    "budgets": [...],
    "attachments": [...],
    "merchantRules": [...],
    "fxRates": [...],
    "autoLedgerSettings": { ... } | null,
    "appPreferences": { "themeMode": "system", ... }
  }
}
```

设计要点：
- `kind` 字段让 restore 端做白名单校验（不是 ledgerly-backup 就拒）；
- `schemaVersion` 用整数，未来 breaking change 走 `migrate(backup)` 通道；
- `summary` 冗余存一份，方便 restore 之前显示预览（不必解析整个 data）；
- 实体 JSON 字段名与现有 Drift 表列名一致，便于 `select(table).get()` → `jsonEncode` 直接序列化。

### 3.2 模块切分

新增 `apps/client/lib/application/backup_service.dart`：

```dart
class BackupService {
  BackupService(this._repo, /* ...其他 repo... */);
  
  Future<BackupDocument> export();         // 生成内存文档
  Future<RestorePreview> previewRestore(BackupDocument doc);
  Future<void> restore(BackupDocument doc); // replace 模式
  Future<void> wipeLocalData();             // 清空
}
```

依赖：`LedgerRepository`、`LocalRecurringRepository`、`LocalBudgetRepository`、`LocalAttachmentRepository`、`LocalMerchantRuleStore`、`AppPreferencesStore`、`AutoLedgerSettingsStore`、`FxRateStore`。

UI：新建 `presentation/pages/data_governance_page.dart`，单页三段式：
1. **备份**（导出）：按钮 + 上次备份时间（如有）；
2. **恢复**（导入）：按钮选文件 → 解析 → 显示预览 → 二次确认 → 执行；
3. **清空本地数据**：危险按钮 → 要求键入 "DELETE" → 执行。

路由：`/settings/governance`（在 `/settings/keyboard` 旁边）。

### 3.3 Replace 模式的安全策略

Restore 是不可逆操作，必须强制 **先自动备份**：

```
[选文件] → [解析 + preview] → [点击"立即恢复"]
  ↓
[自动写入 <tmp>/ledgerly-pre-restore-<ts>.json]
  ↓
[弹窗: "恢复将覆盖当前 N 条数据。已自动备份到 <路径>。是否继续？"]
  ↓ (用户确认)
[事务: BEGIN → 清空所有表 → 按顺序插入备份数据 → COMMIT]
  ↓
[刷新所有 Riverpod provider → snackbar 报告]
```

如果恢复失败（事务回滚），用户仍可手动从 pre-restore 文件救回。

### 3.4 Wipe 二次确认

```
[点击"清空本地数据"]
  ↓
[弹窗: 输入框 + 提示"请输入 DELETE 确认"]
  ↓ (用户输入 DELETE + 点击"确认清空")
[事务: 清空所有表 + 重置 app preferences 关键字段]
  ↓
[重启到 /auth 或 /startup]
```

### 3.5 文件存储

- 写入：用 `path_provider.getApplicationDocumentsDirectory()` 拿到 App 沙盒，文件名 `ledgerly-backup-2026-09-13.json`；
- 通过 `share_plus` / 系统分享面板让用户保存到任意位置；
- 读取：用 `file_picker` 选 `.ledgerly.json` 文件。

### 3.6 i18n 新增键

en / zh 各加：
- `dataGovernanceTitle`
- `dataGovernanceSubtitle`
- `dataGovernanceBackup`
- `dataGovernanceBackupAction`
- `dataGovernanceLastBackupAt`
- `dataGovernanceRestore`
- `dataGovernanceRestoreAction`
- `dataGovernanceRestorePreview` (含 N 条数据)
- `dataGovernanceRestoreConfirmTitle`
- `dataGovernanceRestoreConfirmBody`
- `dataGovernanceRestoreSuccess`
- `dataGovernanceWipe`
- `dataGovernanceWipeAction`
- `dataGovernanceWipeConfirmTitle`
- `dataGovernanceWipeConfirmBody`
- `dataGovernanceWipeConfirmHint` ("输入 DELETE")
- `dataGovernanceImportFailed` (版本不匹配/JSON 损坏)
- `dataGovernanceBackupFailed`
- `dataGovernancePreRestoreBackupPath`

## 4. 实现清单

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `docs/design/phase-6-data-governance.md` | 新增 | 本文档 |
| 2 | `apps/client/lib/application/backup_service.dart` | 新增 | export / preview / restore / wipe |
| 3 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 新增 | 三段式 UI |
| 4 | `apps/client/lib/routing/app_router.dart` | 修改 | 注册 `/settings/governance` |
| 5 | `apps/client/lib/presentation/widgets/settings_content.dart` | 修改 | 新增"数据治理"入口（可为空） |
| 6 | `apps/client/lib/presentation/pages/settings_page.dart` | 修改 | 传 `onGovernance` 回调 |
| 7 | `apps/client/lib/l10n/app_en.arb` | 修改 | ~18 键 |
| 8 | `apps/client/lib/l10n/app_zh.arb` | 修改 | ~18 键 |
| 9 | `apps/client/test/widget/data_governance_page_test.dart` | 新增 | 4-5 个 case |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| Restore 中途崩溃导致数据库半空 | 全部 restore 包在单一 Drift `transaction { }` 里，失败自动回滚 |
| 用户不小心点了"清空本地数据" | 强制键入 `DELETE`，文案红色强调 |
| 备份文件被未来版本破坏 | `schemaVersion` 不匹配时拒绝并提示 |
| 备份文件含敏感信息 (金额/账户) | v1 不上云，仅本地导出 + 系统分享；后续 v2 加可选密码 |
| 大账本 (10000+ 笔) JSON 编码慢 | v1 同步内存；v2 改流式 + gzip |
| 跨设备 restore 后 deviceId 冲突 | 备份保留旧 deviceId，恢复后用新 deviceId 写 sync state；冲突由现有同步引擎兜底 |

## 6. 验收

- [ ] `flutter analyze` 无新增 warning/error；
- [ ] `flutter test test/widget/data_governance_page_test.dart` 通过；
- [ ] 手动跑通：
  - 导出 → 文件落盘 → 用文本编辑器打开能看到账本骨架；
  - 导入同一文件 → 预览正确 → 确认 → 数据替换成功；
  - 清空 → 输入 DELETE → 数据库为空 → 跳到 /startup。