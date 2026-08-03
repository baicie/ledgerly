# ADR-BE-010：乐观版本而非全局锁

* 状态：Accepted
* 日期：2026-08-03

## 决策

实体 `version` + CAS UPDATE。默认 READ COMMITTED。优先条件 UPDATE；持锁禁外部调用；设置 lock_timeout。
