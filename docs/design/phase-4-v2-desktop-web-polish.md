# Phase 4 v2 — Desktop & Web 体验打磨

## 1. 背景与动机

Roadmap Phase 4（Web/桌面）已落地最小可用结构：

- `ShellPage` 在 `width >= 900` 时切到 `NavigationRail`，否则 `BottomNavigation`；
- 全平台（`web`/`windows`/`macos`/`linux`）配置齐全；
- `Cmd/Ctrl + N` 触发快速记账；
- ARB 多语言、`go_router` 路由一致。

但桌面/Web 用户体验仍存在明显短板：

1. **快速记账在大屏上仍是底部弹层**。`openQuickEntry` 永远走 `showModalBottomSheet`，即使在 1440px 窗口上也像手机 UX，键鼠用户没有"对话框居中"的预期；
2. **缺少命令面板**。桌面/Web 用户期待 `Cmd/Ctrl + K` 模糊搜索跳转。Ledgerly 现在 18+ 路由（feed/accounts/reports/settings + 13 个子页），用户必须层层点击；
3. **没有快捷键可见性**。Settings 里没有列出可用快捷键，新用户无从发现 `Cmd/Ctrl + N`、`Cmd/Ctrl + K`、`Esc` 关闭等；
4. **缺少自适应 Dialog 工具**。后续所有弹窗（确认、详情）都可能踩到同样问题——窄屏 sheet，宽屏 dialog。

本阶段在已有结构上做"用户可感知的桌面/Web 体验打磨"，不引入新依赖。

## 2. 目标 / 非目标

### 目标
- **G1**：快速记账在 `width >= 900` 时改为居中 Dialog，窄屏维持 Bottom Sheet 行为；
- **G2**：实现 `Cmd/Ctrl + K` 命令面板，覆盖全部 18+ 路由 + 2 个全局动作（新建流水、立即同步），支持键盘上下选择/回车执行/Esc 关闭；
- **G3**：新增"键盘快捷键"页（`/settings/keyboard`），列出全部可用快捷键并提供一键触发；
- **G4**：所有新代码带 widget 测试，至少覆盖：
  - 自适应：900px 以下用 sheet、以上用 dialog；
  - 命令面板：空查询/有查询/无匹配/键盘导航；
  - 快捷键页：列表项渲染与点击跳转。

### 非目标
- 不引入命令面板引擎（不引入 `commander`/`fuzzy` 等）；
- 不改路由架构（保留 `go_router` + `StatefulShellRoute`）；
- 不做窗口大小记忆（OS 层负责）；
- 不实现命令面板的"插件/扩展点"——只硬编码当前命令列表；
- 不做主题切换（已有 Material 3 系统主题）；
- 不引入国际化新 locale，只在已有 zh/en 上加键。

## 3. 设计

### 3.1 自适应容器

新建 `presentation/utils/adaptive.dart`：

```dart
const double kWideBreakpoint = 900;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;
```

后续所有"弹层组件"（quick entry、command palette、confirm dialogs）都基于 `isWide(context)` 决定走 `showDialog` 还是 `showModalBottomSheet`。这样设计文档就是这套约定的事实来源。

### 3.2 自适应快速记账

`presentation/quick_entry.dart` 重构：

- `QuickEntrySheet` 拆掉外层 `Material(shape: ...)` 与 `SafeArea`，只返回 `Column` 表单内容（保持 `_buildForm` 已有逻辑）；
- `openQuickEntry`：
  - `isWide`：用 `showDialog` + `Dialog(insetPadding: 24)` + `ConstrainedBox(maxWidth: 520, maxHeight: 720)`，外层 `Material` 圆角 `16`；
  - 窄屏：保留现有 `showModalBottomSheet` 行为（高度因子 1/0.94/0.76）。

理由：
- 表单内容稳定，单纯改容器；
- 现有 key（`quick-entry-date`/`quick-category-field`/`quick-entry-note`/`quick-entry-save`）保持不变 → 集成测试无需改；
- 移动端用户不受影响。

### 3.3 命令面板

新建 `presentation/widgets/command_palette.dart`：

```dart
class CommandPaletteAction {
  final String id;
  final String label;
  final List<String> searchTerms; // 中文/英文/拼音首字母/同义词
  final IconData icon;
  final String? shortcut;
  final VoidCallback onActivate;
}

Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandPaletteAction> actions,
});

class _CommandPaletteDialog extends StatefulWidget { ... }
```

UI 形态：
- 顶部 `TextField` 自动聚焦，占位符 "输入命令或搜索…"；
- 中部 `ListView` 渲染匹配项（label + icon + 可选 shortcut 标签）；
- 高亮当前选中项；
- 底部状态栏 `Esc 关闭 · ↑↓ 选择 · ↵ 执行`。

交互：
- 输入实时过滤：`label.contains(query) || searchTerms.any((t) => t.contains(query))`（大小写不敏感）；
- `ArrowDown`/`ArrowUp` 移动高亮（自动滚动到可视区）；
- `Enter` 触发当前项 `onActivate` 后关闭；
- `Esc` 关闭；
- 空匹配时显示 `commandPaletteNoResults`。

注册命令（`shell_page.dart` 在 `BuildContext` 里组合）：

| id | label (zh) | shortcut | route |
|---|---|---|---|
| `nav-feed` | 流水 | — | `/feed` |
| `nav-accounts` | 资产 | — | `/accounts` |
| `nav-reports` | 报表 | — | `/reports` |
| `nav-settings` | 我的 | — | `/settings` |
| `nav-sync` | 同步中心 | — | `/settings/sync` |
| `nav-conflicts` | 冲突列表 | — | `/settings/conflicts` |
| `nav-budgets` | 预算 | — | `/settings/budgets` |
| `nav-categories` | 分类 | — | `/settings/categories` |
| `nav-recurring` | 周期记账 | — | `/settings/recurring` |
| `nav-export` | 导出 | — | `/settings/export` |
| `nav-import` | 导入 | — | `/settings/import` |
| `nav-attachments` | 附件 | — | `/settings/attachments` |
| `nav-auto-ledger` | 自动记账 | — | `/settings/auto-ledger` |
| `nav-merchant-rules` | 商户规则 | — | `/settings/auto-ledger/rules` |
| `nav-ai` | AI 助手 | — | `/settings/ai` |
| `nav-subscription` | 订阅 | — | `/settings/subscription` |
| `nav-fx` | 汇率 | — | `/settings/fx` |
| `nav-family` | 家庭邀请 | — | `/settings/family` |
| `action-new` | 新建流水 | `Cmd/Ctrl+N` | 打开 quick entry |
| `action-sync` | 立即同步 | — | 触发 sync |

调用方式（`shell_page.dart`）：

```dart
CallbackShortcuts(
  bindings: {
    const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => openQuickEntry(context),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => openQuickEntry(context),
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _openPalette(context, ref),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _openPalette(context, ref),
  },
  child: Focus(autofocus: true, child: Scaffold(...)),
)
```

`_openPalette` 组装命令列表（`ref.read(syncCenterControllerProvider).syncNow()` 触发同步），弹窗。

### 3.4 键盘快捷键页

新建 `presentation/pages/keyboard_shortcuts_page.dart`：
- 顶部 AppBar：标题"键盘快捷键 / Keyboard Shortcuts"（l10n）；
- 分组列表（`SettingsListSection`）：

| 分组 | 动作 | 绑定 |
|---|---|---|
| 通用 | 打开命令面板 | `Cmd/Ctrl + K` |
| 通用 | 关闭弹窗 | `Esc` |
| 记账 | 新建流水 | `Cmd/Ctrl + N` |
| 同步 | 立即同步 | 命令面板触发 |

每行右侧显示键位 chip；点击行可触发该动作（跳到 quick entry / 打开命令面板）。

### 3.5 路由 & 设置入口

- `app_router.dart`：在 `/settings` 下新增 `path: 'keyboard'` 子路由 → `KeyboardShortcutsPage`；
- `settings_page.dart`：在"系统"分组下加 `ListTile` 入口（icon `keyboard_outlined`），跳 `/settings/keyboard`。

### 3.6 国际化

新增 ARB 键（en + zh）：

```
commandPaletteTitle
commandPaletteHint
commandPaletteNoResults
commandPaletteNavigation
commandPaletteActions
commandPaletteStatus
keyboardShortcutsTitle
keyboardShortcutsGeneral
keyboardShortcutsBookkeeping
keyboardShortcutsCloseDialog
keyboardShortcutsOpenPalette
keyboardShortcutsNewTransaction
keyboardShortcutsTriggerSync
keyboardShortcutsShortcutChipMac
keyboardShortcutsShortcutChipWin
```

## 4. 实现清单

| # | 文件 | 操作 | 说明 |
|---|---|---|---|
| 1 | `docs/design/phase-4-v2-desktop-web-polish.md` | 新增 | 本文档 |
| 2 | `apps/client/lib/presentation/utils/adaptive.dart` | 新增 | `isWide` + `kWideBreakpoint` |
| 3 | `apps/client/lib/presentation/quick_entry.dart` | 重构 | 自适应 Dialog/Sheet |
| 4 | `apps/client/lib/presentation/quick_entry_sheet.dart` | 微调 | 拆掉外层 Material/SafeArea |
| 5 | `apps/client/lib/presentation/widgets/command_palette.dart` | 新增 | 命令面板 |
| 6 | `apps/client/lib/presentation/pages/keyboard_shortcuts_page.dart` | 新增 | 快捷键页 |
| 7 | `apps/client/lib/presentation/pages/shell_page.dart` | 修改 | 注册 Cmd/Ctrl+K，构造命令列表 |
| 8 | `apps/client/lib/routing/app_router.dart` | 修改 | 注册 `/settings/keyboard` |
| 9 | `apps/client/lib/presentation/pages/settings_page.dart` | 修改 | 加键盘入口 |
| 10 | `apps/client/lib/l10n/app_en.arb` | 修改 | 新增 ~15 键 |
| 11 | `apps/client/lib/l10n/app_zh.arb` | 修改 | 新增 ~15 键 |
| 12 | `apps/client/test/widget/quick_entry_adaptive_test.dart` | 新增 | 自适应布局测试 |
| 13 | `apps/client/test/widget/command_palette_test.dart` | 新增 | 命令面板测试 |
| 14 | `apps/client/test/widget/keyboard_shortcuts_page_test.dart` | 新增 | 快捷键页测试 |

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `QuickEntrySheet` 拆掉外层 Material 后与现有 bottom sheet 集成测试（如 `two_device_harness`）失配 | 现有集成测试用 `find.byType(QuickEntrySheet)` 找 widget，保留表单 key，dialog/sheet 都通过 |
| 命令面板中文/英文匹配不准 | `searchTerms` 由调用方提供（同时给中英文 + 同义词），不做拼音转换 |
| ARB 新键缺失占位符导致上次同类问题复发 | 所有新键均为纯字符串，无占位符 |
| Cmd+K 与系统快捷键冲突（macOS Connect to Server） | macOS 上 `Cmd+K` 默认未占用；为安全起见在文档中注明，可后续移除绑定 |
| 命令面板在 dialog 中再开 dialog 出现 `Navigator` 栈问题 | 命令面板 `showDialog` 顶层，内部用 `Navigator.pop` 关自己，不 push 新路由 |

## 6. 验收

- [ ] `flutter analyze` 无 warning/error；
- [ ] `flutter test test/widget/quick_entry_adaptive_test.dart` 通过；
- [ ] `flutter test test/widget/command_palette_test.dart` 通过；
- [ ] `flutter test test/widget/keyboard_shortcuts_page_test.dart` 通过；
- [ ] 桌面构建 `flutter build windows` 成功；
- [ ] 手动验证：
  - 桌面窗口 `Cmd+N` 弹居中 dialog、`Cmd+K` 弹命令面板；
  - 移动端 quick entry 仍为底部 sheet；
  - 命令面板输入"流水"/"feed"/"feed"/"同步"均能命中。