# Ledgerly CONTEXT

* 更新日期：2026-08-04
* 产品：个人及家庭多端记账、资产管理、预算与财务分析
* 首发平台：Android、iOS、Web（应用壳）
* 后续：Windows、macOS

## 产品本质

不是普通云端 CRUD。客户端 Local-first：每台设备持有本地账本副本，未配置 API 时可纯本地运行；服务端负责可选的多设备最终收敛、幂等 Mutation、复式完整性、权限与审计。

## 技术基线

| 层 | 选型 |
|----|------|
| 客户端 | Flutter + Riverpod + Drift + SQLite/WASM |
| 后端 | Rust + Axum + Tokio + SQLx + PostgreSQL |
| 架构 | 模块化单体；单二进制多运行模式 |
| 记账 | 复式记账；金额用整数最小单位 |
| 同步 | Mutation + Change Log；Push/Pull/Bootstrap |
| 任务 | PostgreSQL Job Table（首期不引入 Redis/MQ） |

## 核心不变量

> 任意一次账目修改，要么业务数据、同步日志和 Mutation Receipt 全部成功，要么全部失败。

衍生规则：

1. UI 唯一业务数据源是本地数据库，不是服务端 API。
2. 账户余额是分录聚合投影，不是不可重建事实。
3. 同币种交易 `SUM(entries.amount_minor) == 0`。
4. 同步游标使用服务端单调序列，禁止客户端时间戳。
5. WebSocket 只唤醒，不承载权威数据。
6. 交易冲突整体冲突，禁止自动字段合并金额/账户。

## 术语表

| 术语 | 含义 |
|------|------|
| Book | 账本，多租户边界 |
| Transaction | 一笔交易头 |
| Entry / 分录 | 交易下的借贷行 |
| Mutation | 客户端发起的幂等变更请求 |
| Receipt | 服务端对 Mutation 的处理回执 |
| Change Log | 服务端单调增量日志 |
| Cursor | 账本级同步高水位 |
| Commit | 同一逻辑提交下的一组变更（如交易+全部分录） |
| Tombstone | 软删除墓碑 |
| HLC | Hybrid Logical Clock，元数据冲突排序辅助 |

## 优先级

```text
数据正确性 > 低资源占用 > 运行稳定性 > 开发速度
```

## 首期部署

单机 2C4G：`ledger-server all` + PostgreSQL + 对象存储（外部 S3 兼容）。
