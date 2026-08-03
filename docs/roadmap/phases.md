# 全阶段路线图

## 本轮（至 Phase 3）

| Phase | 名称 | 说明 |
|-------|------|------|
| Docs | 架构基线 | CONTEXT + ADR + roadmap |
| 0 | 领域模型 | `ledger_domain` 纯 Dart |
| 1 | 离线 MVP | Flutter + Drift 单机记账 |
| BE-0 | 服务端骨架 | Axum / migrate / health / all mode |
| BE-1 | Identity | 注册登录 JWT Refresh Device |
| BE-2 | Ledger | 服务端复式写入与 CAS |
| 2 | 同步闭环 | Push/Pull/Bootstrap 双设备 |
| 3 | 移动端产品 | 快速记账/流水/报表/同步/冲突 |

## 后续（仅规划，本轮不建分支）

### Phase 4：Web 与桌面

- Flutter Web / Windows / macOS
- 响应式布局、键盘快捷键
- CSV/Excel 导入、批量编辑

### Phase 5：商业化能力

- 家庭共享账本、预算、周期记账
- 附件、多币种增强、历史版本
- 高级报表、订阅权益

### Phase BE-5 / BE-6（后端扩展）

- Job Worker：周期、通知、缩略图、导入
- OpenTelemetry、限流、备份恢复、压测与资源验收

## 推荐合并顺序

```text
docs/architecture-baseline
  → mvp/phase-0-domain
  → mvp/phase-1-offline  ⎫ 可与 BE-0/1 短并行
  → mvp/phase-be-0-skeleton ⎭
  → mvp/phase-be-1-identity
  → mvp/phase-be-2-ledger
  → mvp/phase-2-sync          # 必须等 BE-2 + 客户端 mutation 队列
  → mvp/phase-3-mobile-product
```
