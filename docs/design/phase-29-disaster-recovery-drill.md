# Phase 29 — 端到端灾难恢复演练

## 1. 背景与动机

Phase 19 的恢复演练会读取、解密并合成备份，但不会把结果写入真实数据库。
因此它仍无法证明以下路径在当前版本中可用：

- 备份可以完整写入一个全新安装；
- 增量合成后的数据可以通过 restore 的约束；
- 加密备份使用正确密码后可以完整恢复；
- 仅外部目录存在的备份导入后可以恢复；
- 所有业务域在恢复后仍保持一致；
- 旧设备的同步游标、待同步操作和冲突不会污染新设备。

本阶段增加隔离数据库恢复矩阵，并用恢复事务显式重置本地同步身份。

## 2. 目标 / 非目标

### 目标

- **G1**：在内存隔离数据库中模拟全新安装；
- **G2**：覆盖明文全量恢复；
- **G3**：覆盖明文 base + incremental 链恢复；
- **G4**：覆盖密码加密恢复；
- **G5**：覆盖仅存在于外部镜像的文件导入并恢复；
- **G6**：恢复后逐项核对账本、账户、交易、分录、周期规则、预算、
  附件元数据、附件字节和商户规则；
- **G7**：replace 恢复清除旧 `pending_mutations`、`sync_conflicts` 和
  `sync_states`；
- **G8**：为每个恢复出的账本建立当前设备、`cursor=0`、无远端绑定的空白
  同步状态；
- **G9**：错误密码不得修改隔离目标中的现有数据。

### 非目标

- 不在生产运行时自动执行真实 replace 恢复；
- 不验证服务端 PostgreSQL 的备份恢复；
- 不恢复或迁移旧设备的同步会话；
- 不替代 Phase 19 的非破坏性 UI 演练；
- 不自动修复损坏、缺失或未登记的外部文件。

## 3. 恢复矩阵

测试使用两个独立 `AppDatabase.forTesting(NativeDatabase.memory())`：
源实例负责生成备份，目标实例先执行全新安装初始化，再执行恢复。

| 场景 | 来源 | 关键路径 |
|---|---|---|
| 明文全量 | `export()` | 文件容器解析 → replace restore |
| 明文增量 | base + delta | 合成完整快照 → replace restore |
| 加密 | `.enc.zip` + 密码 | 解密 → 解析完整快照 → replace restore |
| 外部导入 | 仅外部文件 | 原子导入 → catalog → 读取 → replace restore |

所有场景使用同一个跨业务域断言：

```text
summary counts
  + entity ID sets
  + attachment bytes
  + merchant rules
  + sync state reset
  -> recovery passed
```

## 4. Replace 恢复的同步语义

备份 payload 不包含设备同步会话。replace 恢复在一个数据库事务中：

1. 删除业务表；
2. 删除 `pending_mutations`；
3. 删除 `sync_conflicts`；
4. 删除 `sync_states`；
5. 写回备份业务数据；
6. 为每个恢复账本建立空白同步状态：

```text
deviceId = 当前安装的设备 ID
cursor = 0
remoteBookId = null
lastError = null
```

这样换机恢复不会重放旧设备待同步操作，也不会让旧游标跳过服务端变更。

## 5. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `backup_service.dart` | replace 恢复时清理并重建同步会话 |
| 2 | `backup_disaster_recovery_test.dart` | 隔离数据库、四路径矩阵、同步重置 |
| 3 | `backup-restore.md` | 增加客户端灾难恢复演练命令 |
| 4 | 设计索引和路线图 | Phase 29 |

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 演练修改生产数据 | 使用独立内存数据库，源和目标实例分离 |
| 只验证容器可读却未真实恢复 | 每条路径执行真实 `BackupService.restore` |
| 单一数据域恢复失败未被发现 | 对 summary、ID 集合和附件字节做统一断言 |
| 旧同步游标污染新设备 | replace 后删除旧状态并重建 `cursor=0` |
| 错误密码留下半恢复数据 | 解密失败发生在数据库事务之前，目标保持不变 |
| 外部备份导入后不可恢复 | 导入、读取、恢复在同一矩阵场景内完成 |

## 7. 验收

- [x] 明文全量可恢复；
- [x] 明文增量链可恢复；
- [x] 加密备份仅正确密码可恢复；
- [x] 外部镜像文件可导入并恢复；
- [x] 八个业务域的数量和实体 ID 一致；
- [x] 附件字节逐字节一致；
- [x] replace 恢复清除旧同步会话；
- [x] 恢复后账本使用当前设备的空白同步状态；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（442/442）。
