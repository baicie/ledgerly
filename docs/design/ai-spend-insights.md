# 设计：客户端 AI 消费总结（DeepSeek V4 Flash）

* 分支：`feat/ai-spend-insights`
* 状态：Implemented
* 日期：2026-08-22
* 相关：ADR-021、ADR-004、ADR-011

## Objective

在不改变 Local-first 账本权威数据源的前提下，让用户用自己的模型密钥生成：

1. **每日消费总结**（本地日历日）
2. **上月消费总结**（进入新月后补齐，产品语义是「每月 1 号给出」）

默认模型为 DeepSeek V4 Flash（`deepseek-v4-flash`）。设置页可选供应商（DeepSeek / OpenCode / 自定义兼容接口），并配置 Key、Base URL、模型，说明用量与语音能力边界。

成功标准：未配置密钥时应用完整可用；配置后打开流水/报表即可看到当日分析，且新月第一次打开会生成上月月报；密钥只留在本机；账本不同步分析结果。

## 语音转文字结论

**DeepSeek V4 Flash 不能语音转文字。**

官方能力是文本 LLM（可选 thinking）。同系列的 `deepseek-v4-flash-vision-exp` 只增加图像输入，仍然不是 ASR。要把语音记一笔，需要独立的语音转写服务（系统语音识别或 Whisper 等），再把文本交给本模型。

本期不做麦克风、录音或 ASR。设置页明确写上该限制，避免用户以为填了 Key 就能说话记账。

## Assumptions

1. 「ds v4 flush」= DeepSeek V4 Flash，OpenAI 兼容 Chat Completions。
2. 「给出」总结指应用内卡片，不是系统推送。移动端无法可靠在 00:01 后台唤醒，因此采用 **打开/回到前台时补齐到期分析**。
3. 用户自备 Key（BYOK）。Ledgerly 服务端不代理模型请求、不保存 Key、不接收分析用账本切片。纯本地模式同样可用。
4. 第一期不做累计用量看板；卡片可展示最近一次调用的 token。余额请看所选供应商控制台（DeepSeek 或 OpenCode Zen）。
5. 分析是设备本地缓存，不进入 Mutation / Change Log。
6. Flutter Web 直连官方域名可能被浏览器 CORS 拦住。设置允许自定义兼容端点；失败时给出明确文案。
7. OpenCode 走 Zen Go 网关（`https://opencode.ai/zen/go/v1`）。预设只包含 Chat Completions 模型；GPT / Claude 走 `/responses` 或 `/messages`，本期不接。该网关无 CORS，**Flutter Web 无法直连**；请用 iOS / Android / 桌面客户端。

## Product contract

### 设置

路径：`/settings/ai`（本地模式可进）。

| 项 | 规则 |
|----|------|
| 供应商 | DeepSeek（默认）、OpenCode、自定义兼容接口。切换时填入该供应商默认 Base URL；若当前模型仍在新预设中则保留 |
| API Key | 必填才会调用模型；Native 进安全存储，Web 尽力加密存储 |
| Base URL | DeepSeek 默认 `https://api.deepseek.com`；OpenCode 默认 `https://opencode.ai/zen/go/v1`；须为 http(s) origin |
| 模型 | 默认 `deepseek-v4-flash`。DeepSeek：`flash` / `pro`。OpenCode：另含 `glm-5.2`、`minimax-m2.5`、`kimi-k2.5`、`big-pickle` 等 Completions 模型。可填自定义 ID |
| 自动分析 | 默认开启。关闭后只保留缓存，需用户点「生成」 |
| 测试连接 | `GET {base}/models`，不发送账本 |
| 用量 | 说明第一期无累计统计；卡片可显示最近 token |
| 能力说明 | 写明当前文本模型无语音转写；分析会把分类、金额、备注发到用户配置的端点 |

### 每日分析

- 周期：设备本地日历日 `[local midnight, next midnight)`，与现有月报 `monthUtcRange` 同一套「本地日 → UTC 区间」。
- 自动补齐：应用回到前台或打开流水/报表时，补 **今天** 和 **昨天**（昨天用于早上才打开 App 的情况）。
- 无收支：写本地 `empty` 记录，**不调用模型**。
- 有账目变更：`inputHash` 变化则视为过期，自动分析开启时重新生成。

### 月报

- 自动只生成 **上一个完整自然月**，不自动生成「本月进行中」月报。
- 任意一天打开都可以补齐缺失的上月月报（1 号没打开也不丢）。
- 报表页对当前选中月份提供「生成 / 重新生成」。用户可主动生成本月月报。
- 每月 1–3 日不再把上月月报插在流水顶部；月报只出现在报表页。

### 展示

- **每日分析**：放在流水页「当天」分组内部（当天分组默认展开）。已配置模型且当前月今天还没有流水时，才在列表上方补一张嵌入式卡片。
- **每月分析**：只放在报表页，紧跟月份选择与汇总卡，始终对应当前选中月份。流水页用入口「每月分析」跳转到报表，不再重复展示月报正文。
- 未配置 Key：卡片内「去配置」，不打断记账。

## Architecture

```text
Presentation (设置 / 卡片)
    → Application (InsightScheduler / InsightService)
        → Domain helpers (period / snapshot / prompt / parser)
        → Infrastructure
            Drift ai_insights（本地缓存）
            Secure store（Key）
            Dio → 用户配置的 Chat Completions
```

- UI 仍只从本地 Drift 读账本；模型输入由本地交易投影而来。
- 新 Dio 客户端，**不**复用带 Cookie / Bearer 的账本 API 客户端。
- DeepSeek 官方接口默认 thinking=on。对本任务关闭 thinking：请求体带 `"thinking": {"type": "disabled"}`（仅当请求打到 `*.deepseek.com`）。OpenCode Zen 即使选用 DeepSeek 模型也不附加该字段，避免网关按严格 OpenAI schema 拒收。

## Data

### 发送给模型的切片

只发分析所需字段，不发账户 ID、设备 ID、Token：

- 周期、币种 CNY
- 收入/支出合计与笔数
- 分类汇总
- 明细：本地时间、类型、金额（元）、分类中文名、截断备注（≤40 字）

日分析发送全部明细。月分析始终发送分类汇总；明细超过 80 笔时只发送金额最高的 80 笔，并标注截断。

### 本地表 `ai_insights`（schema v6，不同步）

用显式 DDL 创建，不加入 Drift `@DriftDatabase` 生成清单，避免误当成账本实体同步。

| 列 | 含义 |
|----|------|
| id | `{bookId}:{kind}:{periodKey}` |
| kind | `daily` / `monthly` |
| period_key | `2026-08-21` 或 `2026-08` |
| period_start / period_end | UTC，end 为开区间 |
| input_hash | 切片指纹，用于过期判断 |
| status | `ready` / `empty` / `error` |
| headline, body_json | 解析后的标题、要点、建议 |
| prompt_tokens, completion_tokens | 最近一次 usage，可空 |
| model, prompt_version, generated_at | 溯源 |

`prompt_version` 本期为 `spend-insight.v1`。

### 模型输出

要求 JSON：

```json
{
  "headline": "一句话结论",
  "highlights": ["要点"],
  "advice": ["建议"]
}
```

解析容忍 markdown 代码块或夹杂文本；失败则把原文当作 headline。

## Commands

```bash
cd apps/client
dart run build_runner build --delete-conflicting-outputs
dart format .
flutter analyze
flutter test test/ai test/auth test/widget_test.dart test/offline_ledger_test.dart test/database_migration_test.dart
```

## Project structure

```text
docs/design/ai-spend-insights.md
docs/adr/021-client-side-ai-insights.md
apps/client/lib/ai/                  # 设置、客户端、周期、服务
apps/client/lib/data/tables.dart     # AiInsights
apps/client/lib/presentation/pages/ai_settings_page.dart
apps/client/lib/presentation/widgets/ai_insight_card.dart
apps/client/test/ai/
```

## Code style

与现有客户端一致：Riverpod 注入、金额用整数最小单位、界面走 l10n（默认中文）、发给模型的 prompt 保持中文、测试可注入 store / Dio / chat client。密钥禁止写入日志、SnackBar 或 insight 表。

## Testing strategy

| 层 | 覆盖 |
|----|------|
| 纯函数 | 日/月区间、1 月跨年、切片指纹、JSON 解析、prompt 不含账户 ID |
| Store | Key 与非机密配置分开读写 |
| HTTP | thinking 关闭、`/models` 探测、401/402 文案 |
| Service | 无 Key 不请求；空账不请求；hash 命中不重复请求；到期任务含昨天与上月 |
| Drift | v5→v6 建 `ai_insights` |
| UI | 设置入口、本地模式可进 `/settings/ai` |
| 回归 | 现有 Feed/Reports 在未配置 Key 时不依赖真实模型 |

## Boundaries

- Always：密钥进安全存储；分析失败不影响记账；空账不调用模型；关闭 thinking。
- Ask first：把分析改成服务端代理、同步 insight、系统推送、接入 ASR。
- Never：把 Key 或账本切片打进日志；把 insight 当 Mutation 上传；把未配置模型写成「已支持语音记账」。

## Risks

| 风险 | 处理 |
|------|------|
| 浏览器 CORS | OpenCode / 多数官方接口无 CORS。网页端给出明确文案，保存仍可用；真正调用请用 App。自定义 Base URL 可指向带 CORS 的网关。 |
| 把过多明细发给模型 | 月报截断 + 备注截断 |
| thinking 费用 | 默认 disabled |
| Web 安全存储弱于 Keychain | 文档说明；Key 仍不进普通业务表 |
| 自定义兼容端点不认 `thinking` | 仅官方 DeepSeek 主机附加该字段 |
| OpenCode 上的 GPT/Claude | 不进预设；用户若手填 ID 仍走 Completions，可能失败 |

## Out of scope

- 语音转文字、拍照认账单、预算建议 Agent、家庭账本联合分析
- 累计 token 看板、余额拉取（`GET /user/balance` 留作二期）
- 服务端代扣费或统一 Key
- iOS/Android 本地通知

## Success criteria

- [x] 设计文档与 ADR-021 入库
- [x] 设置可保存 Key / URL / 模型 / 自动分析，并可测试连接
- [x] 未配置时可记账；配置且自动分析开启时补齐今/昨日报与上月月报
- [x] 流水与报表展示结构化结论；可手动重新生成
- [x] V4 Flash 无语音能力写在设置页
- [x] schema v6 迁移测试通过；`ai_insights` 不参与同步
- [x] CI 执行 `apps/client/test/ai`
