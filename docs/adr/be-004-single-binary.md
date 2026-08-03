# ADR-BE-004：单二进制多运行模式

* 状态：Accepted
* 日期：2026-08-03

## 决策

`ledger-server api|worker|all|migrate|doctor`。小规模用 `all`；扩展后拆 api/worker，同镜像。
