# ADR-BE-019：健康检查和优雅关闭

* 状态：Accepted
* 日期：2026-08-03

## 决策

`/health/live|ready|startup`。SIGTERM：Not Ready → 停新请求 → 排空 → 停 Job 领取 → 关 WS → flush telemetry → 关池。窗口 30s。
