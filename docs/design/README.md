# 阶段设计文档

每个阶段在写业务代码前必须完成本目录对应设计文档并合并（或至少在阶段分支上就绪）。

| 文档 | 阶段 |
|------|------|
| [phase-0-domain.md](./phase-0-domain.md) | 领域模型 |
| [phase-1-offline-mvp.md](./phase-1-offline-mvp.md) | 离线 MVP |
| [phase-be-0-skeleton.md](./phase-be-0-skeleton.md) | 服务端骨架 |
| [phase-be-1-identity.md](./phase-be-1-identity.md) | Identity |
| [phase-be-2-ledger.md](./phase-be-2-ledger.md) | 服务端 Ledger |
| [phase-2-sync-loop.md](./phase-2-sync-loop.md) | 同步闭环 |
| [phase-3-mobile-product.md](./phase-3-mobile-product.md) | 移动端产品 |
| [production-auth-session.md](./production-auth-session.md) | 生产认证会话 |
| [0.0.3-user-configurable-api.md](./0.0.3-user-configurable-api.md) | 0.0.3 用户配置 API 地址 |
| [0.0.4-optional-api-local-mode.md](./0.0.4-optional-api-local-mode.md) | 0.0.4 可选 API 与纯本地模式 |
| [ai-spend-insights.md](./ai-spend-insights.md) | 客户端 BYOK 消费总结（DeepSeek / OpenCode） |
| [client-i18n.md](./client-i18n.md) | 客户端国际化（默认中文） |
| [local-daily-tools.md](./local-daily-tools.md) | 搜索、应用锁、本地预算/周期/导入/附件 |
| [daily-tools-0.0.16.md](./daily-tools-0.0.16.md) | 导入/周期/预算/附件打磨、生物识别、minSdk 24 |
| [insights-0.0.17.md](./insights-0.0.17.md) | 历史日报、内置提示词、生成动效、compileSdk 37 |
| [phase-6-data-governance.md](./phase-6-data-governance.md) | 备份 / 恢复 / 清空 |
| [phase-7-backup-health.md](./phase-7-backup-health.md) | 备份健康追踪 |
| [phase-8-selective-backup.md](./phase-8-selective-backup.md) | 按账本选择备份 |
| [phase-9-attachment-bundling.md](./phase-9-attachment-bundling.md) | 附件二进制打包 |
| [phase-10-password-encrypted-backup.md](./phase-10-password-encrypted-backup.md) | 密码加密备份 |
| [phase-11-argon2id-kdf.md](./phase-11-argon2id-kdf.md) | Argon2id 密钥派生 |
| [phase-12-auto-backup.md](./phase-12-auto-backup.md) | 打开应用时的自动备份调度 |
| [phase-13-merge-restore.md](./phase-13-merge-restore.md) | 跨账本 merge 恢复 |
| [phase-14-incremental-backup.md](./phase-14-incremental-backup.md) | 增量 diff 备份 |
| [phase-15-backup-retention.md](./phase-15-backup-retention.md) | 备份目录与保留策略 |
| [phase-16-portable-consolidation.md](./phase-16-portable-consolidation.md) | 增量备份便携化 |
| [phase-17-backup-integrity.md](./phase-17-backup-integrity.md) | 备份完整性检查 |

状态：文档在对应阶段分支创建并完善；基线阶段仅保留本索引。
