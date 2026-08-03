# Phase 5+ 增量：鉴权 / 预算进度 / 周期入账

* 分支：`mvp/phase-remaining`
* 日期：2026-08-03
* 状态：**已实现并验收（测试绿）**

## 范围

1. **JWT 鉴权**：sync / commercial / ledger 路由要求 `Authorization: Bearer`；校验账本成员资格。
2. **预算进度**：`list_budgets` 返回 `spentMinor` / `remainingMinor`（按 `categoryAccountId` 本月分录汇总）。
3. **周期入账**：`enqueue_recurring_scan` 将到期规则写成交易 + `sync_changes`，并推进 `next_run_at`；支持 `runNow`。

## 非目标

- 真对象存储 / Ed25519 JWT / OpenTelemetry
