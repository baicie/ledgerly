# ADR-BE-012：Bootstrap 一致性快照语义

* 状态：Accepted
* 日期：2026-08-03

## 决策

记录高水位 cursor → 分页导出 → 客户端导入 → 从高水位 Pull。不长持 PG 事务。Cursor 过期返回 SYNC_CURSOR_EXPIRED + bootstrapRequired。
