# ADR-BE-011：Pull 服务端单调游标

* 状态：Accepted
* 日期：2026-08-03

## 决策

`sequence > cursor` 正序；默认 limit 500 max 1000。分页不得拆开同一 commit_id；nextCursor 指向完整 Commit 末尾。
