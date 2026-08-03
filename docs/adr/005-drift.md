# ADR-005：统一使用 Drift，执行器按平台区分

* 状态：Accepted
* 日期：2026-08-03

## 决策

- Native：Drift → NativeDatabase → SQLite（可加密）
- Web：Drift → WASM → OPFS/Browser Storage，并标明存储模式降级

迁移必须版本化、事务化；同步协议版本与数据库版本独立；迁移完成前不启动同步。
