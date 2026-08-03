# ADR-BE-022：测试策略

* 状态：Accepted
* 日期：2026-08-03

## 决策

Domain / 真实 PG Repository / 同步 E2E / 并发 / Property test。覆盖幂等、CAS、Job SKIP LOCKED、Commit 原子。
