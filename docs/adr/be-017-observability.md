# ADR-BE-017：tracing + OpenTelemetry

* 状态：Accepted
* 日期：2026-08-03

## 决策

统一 tracing。Span：http/auth/ledger/sync/postgres/job/object_storage。禁止记录账目正文、精确金额、Token、完整 Payload。
