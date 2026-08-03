# Phase BE-0：服务端骨架

* 分支：`mvp/phase-be-0-skeleton`
* ADR：BE-000/004/005/007/019/020

## 目标

`ledger-server` 单二进制支持 `api|worker|all|migrate|doctor`；health；PgPool；tracing；优雅关闭。

## 验收

- [x] `cargo build -p ledger-server`
- [x] `ledger-server doctor` 打印配置
- [x] `/health/live` 不访问数据库
