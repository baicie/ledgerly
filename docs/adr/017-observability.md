# ADR-017：可观测性

* 状态：Accepted
* 日期：2026-08-03

## 决策

后端 tracing + OpenTelemetry。关键指标含 sync_*、ledger_unbalanced_rejected_total 等。禁止上传具体账目内容。
