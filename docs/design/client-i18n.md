# 设计：客户端国际化（默认中文）

* 分支：`feat/i18n-insight-placement`
* 状态：Implemented
* 日期：2026-08-22
* 相关：ADR-022、[ai-spend-insights.md](./ai-spend-insights.md)

## Objective

把客户端用户可见文案从硬编码中文改为 Flutter `gen-l10n`，并让 **中文成为默认与回退语言**。系统语言为英语时用英语，其它语言回退中文。

发给模型的消费分析 prompt 与账本切片分类名保持中文，不随界面语言切换。

## Assumptions

1. 第一期只维护 `zh` / `en` 两套 ARB。
2. 用户自定义分类、备注、账户名按原样显示，不翻译。
3. 内置分类与现金/银行卡等种子账户按规范名映射到 l10n。
4. 测试不强制包一层 `AppLocalizations`：无 delegate 时回退中文，现有断言继续成立。

## Product contract

| 项 | 规则 |
|----|------|
| 模板语言 | `app_zh.arb` |
| 回退 | 非 `en` 一律 `zh` |
| 英语 | 系统 `languageCode == en` 时启用 |
| 设置 | 第一期不提供应用内语言开关，跟随系统 |
| 模型 | `insight_prompt.dart` 与切片分类中文名保持不变 |

## Architecture

```text
MaterialApp
  localeResolutionCallback → L10n.locale
  delegates: AppLocalizations + GlobalMaterialLocalizations
Widget
  l10nOf(context) → AppLocalizations.of ?? lookupAppLocalizations(zh)
非 Widget（异常、HTTP 文案）
  L10n.current
```

生成文件输出到 `apps/client/lib/l10n/`（`synthetic-package: false`），随仓库提交。

## Commands

```bash
cd apps/client
flutter gen-l10n
flutter analyze
flutter test test/ai test/auth test/widget_test.dart test/offline_ledger_test.dart test/database_migration_test.dart
```

## Success criteria

- [x] 界面文案走 ARB；默认与回退为中文
- [x] 英语系统可切换到英文界面
- [x] 发给模型的 prompt 仍为中文
- [x] 现有以中文断言的 widget 测试在无显式 locale 时仍通过
