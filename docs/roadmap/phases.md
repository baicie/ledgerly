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

## 增量便携化（Phase 16）

- [x] 将本机基础全量与最新增量合成为独立全量备份
- [x] 新文件使用新 ID，登记为手工备份并永久保护
- [x] 更新 last/base，后续增量以新全量为基线
- [x] 最近备份已是全量时 no-op
- [x] 删除旧 base/delta 后，新文件仍可独立恢复

## 备份完整性（Phase 17）

- [x] catalog 记录备份文件 SHA-256
- [x] 检查 full / incremental / encrypted 文件存在性与容器可读性
- [x] 区分 healthy / missing / corrupted，且不修改或删除文件
- [x] 旧 catalog 记录首次检查时自动补算 hash
- [x] 数据治理页提供完整性检查和异常路径明细

## 加密便携备份（Phase 18）

- [x] 便携化流程支持可选密码
- [x] 留空生成明文，非空生成 Argon2id + AES-256-GCM 加密文件
- [x] 加密产物使用新 ID，登记为手工加密备份
- [x] 明文合成更新 last/base，加密合成只更新 last
- [x] 删除旧 base/delta 后仍可用密码独立恢复
- [x] 错误密码不可恢复
- [x] 数据治理页提供可选密码对话框和 8 位校验

## 备份恢复演练（Phase 19）

- [x] 最近备份支持非破坏性恢复演练
- [x] 明文增量实际完成 base + delta 合成
- [x] 加密备份支持输入密码后解密演练
- [x] 校验实体 ID、summary 行数与附件索引
- [x] 验证附件二进制大小和 SHA-256
- [x] 演练过程不修改当前数据库、文件或 metadata
- [x] 数据治理页提供入口、密码重试和结果摘要

## 备份目录逐项操作（Phase 20）

- [x] catalog 记录增量文件的 baseBackupId
- [x] 历史增量按目录中的基础文件恢复，不依赖当前 base
- [x] 目录展示类型、来源、时间、大小、路径和状态标识
- [x] 任意明文/加密目录项可独立演练
- [x] 目录项可加载恢复预览、分享和确认式删除
- [x] 当前 base、latest 和被依赖文件禁止删除
- [x] 旧 catalog 记录在读取或校验时补全 baseBackupId

## 加密备份密码轮换（Phase 21）

- [x] 指定加密备份支持旧密码 + 新密码轮换
- [x] 使用新 backupId 和 Argon2id + AES-256-GCM 重新封装
- [x] 原文件保留，仍可使用旧密码恢复
- [x] 新文件可使用新密码独立恢复
- [x] latest 轮换更新 metadata，历史文件轮换不影响 latest/base
- [x] 旧密码错误和短新密码被拒绝
- [x] 文件名加入 backupId 后缀，避免同分钟覆盖
- [x] 数据治理页提供三字段密码轮换对话框

## 加密自动备份（Phase 22）

- [x] schedule 支持持久化加密自动备份偏好
- [x] 自动备份密码保存到系统安全存储
- [x] 加密模式始终生成独立加密全量
- [x] 加密自动备份不更新增量 base
- [x] 缺少密码或安全存储异常时跳过，不写明文
- [x] 关闭加密模式时清除保存的密码
- [x] 数据治理页提供开关、设置密码和状态说明

## 恢复审计（Phase 23）

- [x] 记录 replace / merge 的成功和失败恢复
- [x] 记录来源 backupId、时间、安全备份路径和 merge 统计
- [x] 失败记录只保存截断后的错误摘要
- [x] 恢复历史最多保留 50 条
- [x] cleanup 保护最近审计关联的安全备份
- [x] 删除历史时同步删除关联安全备份
- [x] 数据治理页展示、分享和删除恢复历史

## 备份策略健康中心（Phase 24）

- [x] 聚合最近备份、cadence、加密密码、目录和恢复状态
- [x] 输出 healthy / warning / critical 健康等级
- [x] 区分无备份、过期、缺密码、缺失、损坏和 base 缺失
- [x] 返回一个按风险排序的推荐操作
- [x] 数据治理页展示原因、目录数量、下次计划和刷新
- [x] 推荐操作复用备份、自动设置和完整性检查
- [x] 操作完成后自动刷新健康状态

## 原子备份写入（Phase 25）

- [x] 备份先写入同目录临时文件并 flush
- [x] 完整写入后原子 rename 到最终路径
- [x] 写入或 rename 失败保留原文件
- [x] 失败清理残留临时文件
- [x] 导出、加密、增量、安全备份统一走原子写入
- [x] 写入失败不更新 metadata 或 catalog
- [x] 增加磁盘写满和 rename 失败故障注入测试

## 备份治理报告（Phase 26）

- [x] 生成含 schemaVersion / generatedAt 的治理报告
- [x] 汇总健康、策略、catalog 和恢复审计统计
- [x] 支持 JSON 完整报告和 CSV 摘要
- [x] 报告不包含路径、backupId、密码、错误摘要或账本内容
- [x] 使用原子写入器保存报告
- [x] 数据治理页支持选择格式并分享
- [x] 报告导出失败不改变任何备份状态

## 外部备份目录（Phase 27）

- [x] 外部备份目录可持久化和清除
- [x] 新备份本地成功后自动镜像
- [x] 选择目录时批量镜像已有 catalog
- [x] 外部写入使用原子文件写入器
- [x] 镜像失败不影响本地备份
- [x] catalog 记录 mirrored / failed 状态
- [x] 健康中心提示目录不可用或镜像失败
- [x] 数据治理页支持选择、清除和立即镜像

## 外部镜像校验（Phase 28）

- [x] 扫描外部目录并与本地 catalog 镜像记录核对
- [x] 区分 healthy / missing / corrupted / extra
- [x] 使用大小和 SHA-256 验证外部副本
- [x] 外部异常进入备份策略健康中心
- [x] extra 文件可原子导入本机并登记 catalog
- [x] 导入失败清理本机副本
- [x] 数据治理页展示异常明细和导入操作

## 端到端灾难恢复演练（Phase 29）

- [x] 使用隔离内存数据库模拟全新安装
- [x] 覆盖明文全量、明文增量、加密和外部导入四条恢复路径
- [x] 统一校验八个业务域、实体 ID 和附件字节
- [x] replace 恢复清除旧待同步操作和冲突
- [x] 每个恢复账本使用当前设备建立 `cursor=0` 的空白同步状态
- [x] 错误密码不修改隔离目标数据
- [x] 增加客户端灾难恢复 Runbook

## 恢复演练审计与就绪度（Phase 30）

- [x] 持久化最近备份和 catalog artifact 的成功/失败演练
- [x] 成功审计记录加密/增量标志与数据数量
- [x] 审计最多保留 20 条并容忍损坏数据
- [x] 健康中心识别未演练、最近失败和超过 90 天
- [x] 健康操作可直接运行恢复演练
- [x] 治理报告 schema v2 汇总演练状态
- [x] 清空本机数据时同步清除演练审计

## 服务端 PostgreSQL 恢复演练（Phase 31）

- [x] 每次演练创建独立源数据库和目标数据库
- [x] 覆盖身份、账本、预算、周期、附件元数据和同步表
- [x] 使用生产 `backup()` / `restore()` 路径
- [x] 恢复后运行 migration 并验证幂等
- [x] 验证备份后标记不会进入恢复结果
- [x] 对比恢复前后表数量快照
- [x] 断言 restore + migrate 小于 4 小时 RTO
- [x] CI 安装 PostgreSQL client 并强制执行

## 对象存储附件灾备（Phase 32）

- [x] 对象目录 manifest 记录 key、大小和 SHA-256
- [x] 备份复制后重新校验对象元数据
- [x] 恢复到 staging 后原子替换目标目录
- [x] 损坏备份失败且不覆盖现有对象
- [x] 上传完成回写真实附件 size/hash
- [x] CLI 支持 `--objects-out` / `--objects-from`
- [x] PostgreSQL 演练联合恢复并交叉校验附件

## 加密备份包与异地复制（Phase 33）

- [x] 数据库 dump 与对象备份统一 bundle manifest
- [x] 原始和存储文件均记录大小与 SHA-256
- [x] 可选 Argon2id + AES-256-GCM 加密
- [x] 逻辑路径作为 AES-GCM AAD
- [x] 支持 verify / unpack / replicate
- [x] 复制完成后重新校验再发布
- [x] PostgreSQL 联合演练经过加密 bundle 全链路

## 流式加密 bundle 与保留策略（Phase 34）

- [x] schema v2 使用 1 MiB 分块 AES-256-GCM
- [x] 每文件随机 nonce 前缀加 chunk index
- [x] 逻辑路径和 chunk index 作为 AAD
- [x] 支持无密码密文验证与有密码明文验证
- [x] 保持 Phase 33 schema v1 bundle 可读
- [x] 新增 bundle cleanup 保留最新 N 份
- [x] CI 联合恢复链路覆盖新格式

## 自动备份编排与验证状态（Phase 35）

- [x] worker 幂等注册并续排 backup job
- [x] 编排 dump、对象、bundle、verify、复制和清理
- [x] 成功/失败状态原子写入 status.json
- [x] `/health/backup` 输出 disabled/never_run/failed/stale/ready
- [x] 健康响应不包含路径和错误详情
- [x] 提供手工 `backup-run` / `backup-status` 命令

## 生产备份部署接线（Phase 36）

- [x] 运行镜像包含 PostgreSQL 16 `pg_dump` / `pg_restore`
- [x] Compose 挂载对象、备份和异地目录
- [x] 环境模板包含加密密码和保留策略
- [x] 部署验收检查 `/health/backup` 和三个可写目录
- [x] 部署验收检查 pg_dump 主版本
- [x] CI 构建服务端镜像并执行备份工具 smoke test

## 一键 Bundle 恢复与审计（Phase 37）

- [x] 恢复前验证 bundle 并自动创建当前状态安全备份
- [x] 一键完成解包、对象恢复、数据库恢复和 migration
- [x] 恢复后逐附件校验 object key、大小和 SHA-256
- [x] 成败均写入 restore-status.json
- [x] `/health/backup` 返回最近恢复摘要
- [x] CLI 强制 `--confirm`
- [x] CI 联合演练改走一键恢复

## 生产定时恢复演练（Phase 38）

- [x] worker 幂等注册并周期续排恢复演练
- [x] 自动选择最新本地/异地 bundle
- [x] 创建临时 PostgreSQL 数据库和临时对象目录
- [x] 恢复后校验 schema、附件和业务数量
- [x] 强制清理临时数据库和目录
- [x] 成败均写入 recovery-drill-status.json
- [x] health 暴露 lastRecoveryDrill
- [x] CI 真实执行生产演练执行器

## 备份告警与容量治理（Phase 39）

- [x] `/metrics` 导出备份、恢复和恢复演练状态
- [x] 备份年龄、耗时和最近运行结果可视化
- [x] 本地/异地 bundle 数量、实际字节和无效目录分离统计
- [x] 容量 warning/critical 阈值可通过环境变量配置
- [x] 运行结果、保留清理失败和采集失败具有 counter
- [x] 提供 Prometheus 告警规则和 Alertmanager/Grafana 示例
- [x] Runbook 明确容量处置和故障排查流程

## 生产观测栈与告警闭环（Phase 40）

- [x] 可选 Compose profile 部署 Prometheus、Alertmanager、Grafana
- [x] 固定镜像版本、持久卷和容器健康检查
- [x] Prometheus 自动抓取服务端并加载备份/平台告警
- [x] Alertmanager 支持必填 webhook 和 resolved 通知
- [x] Grafana 自动配置数据源和 Ledgerly Operations 仪表盘
- [x] 部署脚本启用后验证目标健康、规则和三个观测服务
- [x] CI 校验 Compose、Prometheus、Alertmanager 和 Grafana 配置
- [x] Runbook 覆盖 SSH 访问、投递测试和故障排查

## 主机与容器资源观测（Phase 41）

- [x] 可选部署 node-exporter 和 cAdvisor
- [x] Prometheus 抓取宿主与容器资源指标
- [x] 8 条磁盘、inode、CPU、内存、重启和 OOM 告警
- [x] 新增 8 panel Host Resources 仪表盘
- [x] 部署验收检查新服务、target 和规则
- [x] CI 校验新增规则与 dashboard
- [x] Runbook 覆盖挂载、权限和资源告警处置

## S3 兼容对象存储（Phase 42）

- [x] local/S3 可配置对象存储后端
- [x] S3 endpoint、bucket、prefix、path-style 和凭据配置
- [x] 附件签名 URL 继续通过服务端代理读写
- [x] 自动备份从 S3 导出，恢复写回 S3 并校验 SHA-256
- [x] 恢复演练继续使用隔离本地目录
- [x] local 到 S3 的 dry-run 和逐对象校验迁移
- [x] readiness 和 Prometheus 对象存储指标
- [x] S3Mock 本地 profile 和 CI 集成测试

### 待后续完善

- 扩大商户分类覆盖（目前第一版关键词匹配）
- 微信/支付宝通知文案随版本变化需更新正则
- 多语言（目前仅中文 + 英文）

## 推荐合并顺序

```text
… → mvp/phase-3-mobile-product → mvp/phase-remaining
```
