# ADR-004：客户端采用 Local-first 数据模型

* 状态：Accepted
* 日期：2026-08-03

## 决策

本地数据库是 UI 唯一业务数据源。写入先本地事务（transaction + entries + pending_mutations），再后台同步。

不采用「先请求 API，失败后读缓存」。
