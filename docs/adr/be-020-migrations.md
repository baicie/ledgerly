# ADR-BE-020：数据库迁移由应用显式执行

* 状态：Accepted
* 日期：2026-08-03

## 决策

SQLx migrate；生产不自动跑未知迁移。流程：`migrate` → `doctor` → `api`。Expand/Contract；启动检查 schema 版本窗口。
