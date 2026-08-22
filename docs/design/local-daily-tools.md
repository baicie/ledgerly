# 设计：日常记账补齐（搜索 / 应用锁 / 本地预算 / 导出 / 导入 / 周期 / 附件）

* 分支：`feat/collapse-ai-insight`
* 状态：Implemented
* 日期：2026-08-22
* 相关：ADR-014、ADR-004、[ai-spend-insights.md](./ai-spend-insights.md)

## Objective

在 Local-first 主路径上补齐日常会用到的产品能力，且不依赖 API：

1. AI 分析卡默认收起
2. 流水搜索
3. 应用锁（PIN）
4. 本地预算
5. CSV 文件导出 / 分享
6. 账单 CSV 导入（草稿确认后入账）
7. 本地周期记账
8. 流水本地附件

## Product contract

| 能力 | 规则 |
|------|------|
| 搜索 | 当前选中月内，按备注、分类、账户、金额子串过滤；有关键字时展开匹配日 |
| 应用锁 | PIN 存安全存储；启用后冷启动与回到前台需解锁；Web / 测试同样走 PIN |
| 预算 | 本地表计算本月支出进度；已登录时仍可用远端预算 API |
| 导出 | 复制 + 保存/分享 UTF-8 CSV（含 BOM） |
| 导入 | 解析 Ledgerly / 支付宝 / 微信常见列名 → 预览勾选 → 写入本地复式交易 |
| 周期 | 本地规则按「每月几号」到期生成交易，打开/回到前台补齐 |
| 附件 | 二进制只留本机，不进 Mutation；元数据在本地表 |

不在本期：语音记账、拍照识别、家庭联合分析、生物识别。

## Architecture

```text
Feed search        → 纯过滤 monthTransactions
App lock           → AppLockStore + overlay
Budgets/Recurring/Attachments → SQLite 本地表（schema v7，不进 Drift @DriftDatabase）
Import             → CsvBillParser → LedgerAppService
Export/Pick file   → UserFilePort（测试可注入）
RecurringScheduler → 与 AI bootstrap 一样在 resume 时跑
```

附件与导入遵守 ADR-014：导入必须经草稿确认；附件二进制不进同步 JSON。
