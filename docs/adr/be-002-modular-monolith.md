# ADR-BE-002：模块化单体

* 状态：Accepted
* 日期：2026-08-03

## 决策

第一阶段单应用部署。模块：identity、device、book、ledger、sync、budget、recurring、import、attachment、notification、audit、subscription。

禁止：Handler 直接 SQL；Sync/Import 绕过 Ledger；模块间 HTTP；每模块独立部署。模块间通过 Application Service。

共享内核仅：UserId/BookId/DeviceId/Money/CurrencyCode/Version/Timestamp/DomainError。
