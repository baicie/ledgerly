# 本轮 MVP 目标与验收

* 状态：Active
* 日期：2026-08-03
* 终点：移动端产品 MVP（Phase 3）

## 目标

交付可日常演示的 Android/iOS 记账应用：

1. 离线完整记账、查询、编辑
2. 双设备 Push/Pull/Bootstrap 最终收敛
3. 快速记账、月度流水、资产账户、分类报表
4. 同步中心与冲突处理页
5. 基础应用锁与最小 CSV 导出

## 后端基线

Rust + Axum + Tokio + SQLx + PostgreSQL（见 ADR-BE-000 / ADR-019）。

## 阶段验收总表

| 阶段 | 分支 | 必须通过 |
|------|------|----------|
| Docs | `docs/architecture-baseline` | ADR 无 Fastify 残留；MVP 边界清晰 |
| Phase 0 | `mvp/phase-0-domain` | 复式不变量单元测试全绿 |
| Phase 1 | `mvp/phase-1-offline` | 离线创建交易立即可查；余额可重算 |
| BE-0 | `mvp/phase-be-0-skeleton` | `ledger-server all` 启动；health 可用 |
| BE-1 | `mvp/phase-be-1-identity` | 注册登录、Refresh rotation、设备下线 |
| BE-2 | `mvp/phase-be-2-ledger` | 不平衡交易拒绝；version CAS |
| Phase 2 | `mvp/phase-2-sync` | 幂等重试、冲突、Cursor 过期、Commit 原子 |
| Phase 3 | `mvp/phase-3-mobile-product` | 主路径可演示；冲突可解决；离线可记账 |

## 本轮不做

- Web/桌面完整产品化
- 家庭共享商业化、预算/周期全量、附件全链路、账单导入全格式
- Redis / Kafka / K8s / 微服务 / E2EE
- 以服务端 API 作为页面主数据源

## 工作流

```text
设计文档 → ADR（如需）→ 实现 → 验收 → 合并 main
```
