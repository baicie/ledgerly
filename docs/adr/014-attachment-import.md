# ADR-014：附件与账单导入独立于普通同步

* 状态：Accepted
* 日期：2026-08-03

## 决策

附件二进制不进同步 JSON；直传对象存储后提交 metadata mutation。导入经 Parser → Draft → 用户确认 → Ledger Application Service，禁止直写正式交易表。
