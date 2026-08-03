# ADR-BE-003：单 Workspace、有限 Crate

* 状态：Accepted
* 日期：2026-08-03

## 决策

首期 crates：`ledger-domain`、`ledger-contracts`、`ledger-testing` + 主二进制 `ledger-server`。业务模块放 `server/src/modules/`，不拆成几十个小 crate。
