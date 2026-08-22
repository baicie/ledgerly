# ADR-022：客户端用 gen-l10n，默认中文

* 状态：Accepted
* 日期：2026-08-22
* 参见：[client-i18n 设计](../design/client-i18n.md)

## 决策

Flutter 客户端用户可见文案使用官方 `gen-l10n`。模板 ARB 为中文；支持 `zh` 与 `en`；解析不到英语时一律中文。

Widget 通过 `l10nOf(context)` 取值；无 localization delegate 时回退 `lookupAppLocalizations(Locale('zh'))`，避免改遍测试里的 `MaterialApp`。

发给模型的分析 prompt 不进入 l10n。

## 理由

1. 产品默认面向中文用户，回退中文比回退英语更符合预期。
2. `gen-l10n` 是 Flutter 标准方案，CI 的 `flutter analyze` / `flutter test` 会生成代码。
3. 测试大量断言中文；nullable getter + 中文回退可以保持现有测试。

## 后果

- 新增文案必须同时写 `app_zh.arb` 与 `app_en.arb`。
- 应用层异常文案会依赖 `L10n.current`，locale 在 `MaterialApp` 解析回调里更新。
- 模型输出与 prompt 仍是中文，英文界面下分析正文可能仍是中文。
