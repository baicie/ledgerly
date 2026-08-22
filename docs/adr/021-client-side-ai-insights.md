# ADR-021：消费分析在客户端调用用户自备模型

* 状态：Accepted
* 日期：2026-08-22
* 参见：[ai-spend-insights 设计](../design/ai-spend-insights.md)、ADR-004、ADR-011

## 决策

AI 消费总结在 **Flutter 客户端** 调用用户配置的 OpenAI 兼容接口。默认供应商 DeepSeek、默认模型 `deepseek-v4-flash`。可选 OpenCode（`https://opencode.ai/zen/go/v1`）或其它兼容端点。API Key 由用户提供并存储在本机。Ledgerly 服务端不转发 Prompt、不保管模型密钥。

分析结果写入本地 SQLite 表 `ai_insights`（schema v6 用显式 DDL 创建，不注册进 Drift 生成 schema，避免误入同步协议），作为可丢弃缓存。

## 理由

1. 产品已支持纯本地模式；分析不应强迫连接账本 API。
2. 账本切片属于敏感财务信息。用户 Key 直连模型服务，责任边界清晰：数据去向是用户选择的供应商，而不是 Ledgerly 云。
3. 服务端代调需要多一套计费、密钥托管与审计，超出本期范围。
4. 分析不是账本事实，同步它们会造成多设备重复计费与冲突。

## 后果

- Web 可能受 CORS 限制，需允许自定义 Base URL，并在失败时说明。
- 同一账本在多台设备会各自生成分析，费用由用户承担。
- 更换设备后需重新填写 Key；旧设备上的 insight 不跟随同步迁移。
