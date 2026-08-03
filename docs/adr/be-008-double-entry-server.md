# ADR-BE-008：服务端复式记账强约束

* 状态：Accepted
* 日期：2026-08-03

## 决策

事实表：transactions + transaction_entries。写入流程含权限、账户归属、币种、平衡校验，再同事务写业务+sync_changes+receipt。金额 DB 用 BIGINT；API 用字符串；Domain 用 i128 并校验 BIGINT 范围。
