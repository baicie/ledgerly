# ADR-BE-014：PostgreSQL Job Table

* 状态：Accepted
* 日期：2026-08-03

## 决策

首期不引入 Redis/MQ。`FOR UPDATE SKIP LOCKED` 领取；领取事务与执行分离；指数退避；幂等业务键；超时回收 Lease。
