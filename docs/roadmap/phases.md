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

## 备份治理（Phase 6–12）

- [x] Phase 6：全量备份 / 恢复 / 清空
- [x] Phase 7：上次备份时间与过期提醒
- [x] Phase 8：按账本子集导出
- [x] Phase 9：附件二进制打进 `.ledgerly.zip`
- [x] Phase 10：可选密码 + AES-256-GCM（`.enc.zip`）
- [x] Phase 11：新加密备份默认 Argon2id；旧 PBKDF2 文件仍可解锁
- [x] Phase 12：打开 / 回到前台时的机会主义自动备份（无后台常驻）

## 跨账本恢复（Phase 13）

- [x] 恢复预览支持替换 / 合并模式
- [x] 不同 ID 账本完整合并，保留本机已有账本
- [x] 仅默认账户且无业务数据的空占位账本可被替换
- [x] 同 ID 已有数据、改过默认账户或有待同步修改时整本跳过
- [x] 附件二进制和商户规则按合并范围处理
- [x] 新增/替换账本重建本地空白同步状态，不恢复旧游标

## 增量备份（Phase 14）

- [x] 全量备份登记本机基础快照 ID 与路径
- [x] 增量文件只保存变更行、删除 ID 和变化附件
- [x] 自动备份优先增量，基础文件缺失时自动回退全量
- [x] 恢复前自动合成完整快照，支持 replace / merge
- [x] 加密导出始终全量；增量文件明确标记仅本机可恢复

## 备份保留（Phase 15）

- [x] 记录本机备份目录：ID、路径、类型、来源、时间、大小
- [x] 区分手工、自动、恢复前安全备份
- [x] 手工备份永久保护；当前基础全量和最近备份强制保护
- [x] 自动备份保留最新 3 份，安全备份保留最新 1 份
- [x] 数据治理页展示数量/占用，并支持确认式清理

### 待后续完善

- 扩大商户分类覆盖（目前第一版关键词匹配）
- 微信/支付宝通知文案随版本变化需更新正则
- 多语言（目前仅中文 + 英文）

## 推荐合并顺序

```text
… → mvp/phase-3-mobile-product → mvp/phase-remaining
```
