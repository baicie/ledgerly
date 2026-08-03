# ADR-BE-021：备份和恢复

* 状态：Accepted
* 日期：2026-08-03

## 决策

PG 定期备份 + 条件允许 WAL/PITR；异地加密备份；每季度恢复演练。初始 RPO≤24h RTO≤4h。
