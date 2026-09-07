# 全阶段路线图

## 已完成（至 Phase 5 骨架）

| Phase | 名称 | 说明 |
|-------|------|------|
| Docs | 架构基线 | CONTEXT + ADR + roadmap |
| 0 | 领域模型 | `ledger_domain` 纯 Dart |
| 1 | 离线 MVP | Flutter + Drift 单机记账 |
| BE-0 | 服务端骨架 | Axum / migrate / health / all mode |
| BE-1 | Identity | 注册登录 JWT Refresh Device |
| BE-2 | Ledger | 服务端复式写入与 CAS |
| 2 | 同步闭环 | Push/Pull/Bootstrap 双设备 |
| 2.5 | 真同步 | Postgres + Dio SyncApi + Sync Center |
| 3 | 移动端产品 | 快速记账/流水/报表/同步/冲突 |
| Remaining | 隔离 + Jobs | 按账本账户 ID、delete mutation、Job Worker |
| 4 | Web/桌面 | Flutter web/windows/macos/linux + NavigationRail + Cmd/Ctrl+N |
| 5 | 商业化骨架 | 邀请/预算/附件上传会话 API + 设置页入口 |

## Phase 5+ / BE-6（`mvp/phase-remaining` 收口）

### Phase 5+

- [x] JWT 鉴权中间件 + 客户端 Bearer
- [x] 预算进度（spent / remaining）
- [x] 周期记账由 Job Worker 生成流水
- [x] 本地 HMAC 对象存储签名上传
- [x] 多币种汇率、历史版本、高级报表、订阅权益

### Phase BE-6

- [x] OpenTelemetry（可选 OTLP）、限流、备份恢复 CLI、压测脚本
- [x] JWT 升级 Ed25519

## feat/auto-ledger（`feat/auto-ledger` 分支）

自动记账管线：Android NotificationListenerService → 通知解析 → SharedPrefs 队列 → Flutter MethodChannel → 去重/分类 → Drift 入账。

- [x] `PayNotificationListener`：系统进程，`onNotificationPosted` 时立即持久化，App 被杀也能捕获
- [x] `PaymentParser`：微信/支付宝正则解析（金额 ¥/￥/元、商户名、收付方向）
- [x] `PaymentEventStore`：SharedPreferences 持久化队列，MAX=200 上限
- [x] `PaymentNotificationService`：MethodChannel 网关，支持 Fake 实现供测试
- [x] `AutoLedgerService`：60s 内存去重 + Ledger 持久层双重去重，7 天过期丢弃，商户分类
- [x] `MerchantClassifier`：常见商户名 → 默认支出/收入分类账户
- [x] `AutoLedgerSettingsPage`：权限状态 / 待处理事件 / 手动同步入口
- [x] Android 单元测试：`PaymentParserTest`（JUnit）
- [x] Flutter 单元测试：`auto_ledger_service_test`、`merchant_classifier_test`、`pending_payment_event_test`
- [x] 210 个 flutter test 全通过

### 待后续完善

- 扩大商户分类覆盖（目前第一版关键词匹配）
- 微信/支付宝通知文案随版本变化需更新正则
- 多语言（目前仅中文 + 英文）

## 推荐合并顺序

```text
… → mvp/phase-3-mobile-product → mvp/phase-remaining
```
