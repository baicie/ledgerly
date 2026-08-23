# 设计：历史日报、内置提示词与生成动效（0.0.17）

* 分支：`feat/insights-0.0.17`
* 状态：Implemented
* 日期：2026-08-23
* 相关：[ai-spend-insights.md](./ai-spend-insights.md)、ADR-021

## Objective

在 `v0.0.16` 之后补齐 AI 分析的三处缺口，并修掉 Android 发版：

1. **历史日报**：流水里每个有账的日期都能看/生成当日分析，不再只挂在「今天」
2. **内置系统提示词**：设置里可选几套分析口吻，也可自己写
3. **生成动效**：点「生成」后立刻有进度，避免误以为没点到
4. **compileSdk 37**：`flutter_secure_storage` 11 在 CI 上需要，否则 APK 打不出来

成功标准：翻到往月/往日能看到日报入口；换提示词后新生成走新口吻；生成中收起也能看见进度；GitHub Release 能挂上 APK。

## Assumptions

1. 自动分析仍只补 **今天、昨天、上月月报**。往日不自动打模型，避免打开往月就发出几十次请求。
2. 发给模型的提示词保持中文，不随界面语言切换。
3. 自定义提示词仍强制 JSON 契约，避免解析失败。
4. `v0.0.16` tag 已打但客户端包失败；本版以 `v0.0.17` 重新出包，不改写旧 tag。

## Product contract

| 项 | 规则 |
|----|------|
| 历史日报 | 选中月份里，每个有流水的日期分组内嵌日分析卡；当天无流水时仍在当月列表上方留一张 |
| 未配置 | 只在「今天」显示去配置；往日不重复堆「去配置」 |
| 已配置未生成 | 显示「尚未生成」和「生成」；点了才调用模型 |
| 已生成 | 展开该日可见正文；分组标题旁有标记 |
| 自动补齐 | 仍是今/昨日报 + 上月月报 |
| 提示词 | 均衡总结（默认）、节约教练、复盘助手、极简结论、自定义 |
| 自定义 | 可编辑系统提示词；空则回退均衡；输出仍必须是 JSON |
| 生成中 | 立刻禁用按钮、顶栏进度条、按钮转圈、文案「正在生成分析…」，并自动展开 |
| Android | `compileSdk = 37`，`minSdk` 保持 24 |

## Architecture

```text
Feed day group
  → monthDailyAiInsightsProvider（本地缓存，不打模型）
  → 点生成 → generatingInsightKeys + InsightService.ensure

Settings
  → AiPromptPreset + optional customSystemPrompt
  → resolveInsightSystemPrompt() + JSON 契约
  → promptVersion = spend-insight.v2:{preset}[:{hash}]
```

换提示词后 `promptVersion` 对不上，自动分析开启时会按到期任务重生成；往日仍需手动点。

## Testing strategy

- 历史日展开后出现日分析卡；未配置时往日不出现配置卡
- 预设提示词进入 Chat Completions 的 system 消息；自定义会拼上 JSON 契约
- 卡片 `busy: true` 时收起状态也能看到进度指示
- 现有今/昨/上月自动补齐回归

## Boundaries

- Always：往日不自动打模型；密钥不进日志；分析结果不同步
- Ask first：打开往月时批量补齐所有日报、服务端代理模型
- Never：把自定义提示词里的密钥或账本原文打进日志

## Success criteria

- [x] 流水历史日可查看并手动生成日报
- [x] 设置页可选内置系统提示词或自定义
- [x] 生成中有可见动效
- [x] Android compileSdk 37
- [x] 客户端版本 0.0.17
