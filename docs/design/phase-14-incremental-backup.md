# Phase 14 — 增量 diff 备份

## 1. 背景与动机

Phase 6–13 的每次备份都会重新打包全部数据与附件。对于财务数据量不大、
但附件图片持续增加的本地记账场景，重复写入几十或几百 MB 的基础文件成本很高。

本阶段增加一层保守的增量备份：

- 保留一份本机可读的基础全量备份；
- 后续备份只记录相对该基础快照发生变化的数据和附件；
- 恢复时由客户端自动读取基础文件并重建完整快照；
- 基础文件缺失或不可读时自动回退为全量备份。

## 2. 目标 / 非目标

### 目标

- **G1**：备份文件增加 `backupId`；增量文件增加 `baseBackupId` 与
  `deleted` 删除索引；
- **G2**：增量数据只写新增/修改行，删除行以 ID 列表记录；
- **G3**：增量附件只打包发生变化或新增的二进制；
- **G4**：schemaVersion 3 表示增量格式；v1/v2 全量文件仍可恢复；
- **G5**：元数据持久化基础备份 ID/路径、当前备份 ID 和当前备份类型；
- **G6**：自动备份优先走增量；没有可用基础文件时自动回退全量；
- **G7**：恢复 replace/merge 前自动合成完整快照；增量链不暴露给 UI；
- **G8**：手动导出提供“增量备份”选项，但加密导出始终是全量；
- **G9**：增量文件只保证本机可恢复。要跨设备分享时必须使用全量备份。

### 非目标

- 不做多级 delta 链；增量始终相对同一份基础全量备份；
- 不做二进制级 rsync；
- 不把增量文件变成可独立恢复的便携文件；
- 不支持加密增量；
- 不自动上传基础文件或增量文件到云盘；
- 不做自动压缩基础文件（压缩策略留给后续）。

## 3. 文件格式

全量备份保持现有 zip 结构：

```text
ledgerly-backup-{ts}.ledgerly.zip
├── manifest.json
├── data.json
└── attachments/*.bin
```

增量备份使用独立后缀：

```text
ledgerly-incremental-{ts}.ledgerly.inc.zip
├── manifest.json
├── data.json          # 仅变更行 + deleted 索引
└── attachments/*.bin  # 仅新增/变化的附件
```

manifest 新增：

```json
{
  "backupId": "uuid",
  "baseBackupId": "base-uuid",
  "schemaVersion": 3,
  "deleted": {
    "books": [],
    "accounts": [],
    "transactions": [],
    "transactionEntries": [],
    "recurringRules": [],
    "budgets": [],
    "attachments": [],
    "merchantRules": []
  }
}
```

全量备份 `baseBackupId == null`，可以成为基础备份。

## 4. 元数据

`BackupMetadataStore` 新增：

| key | 含义 |
|---|---|
| `lastBackupId` | 最近一次成功导出的备份 ID |
| `lastBackupIncremental` | 最近一次是否为增量文件 |
| `baseBackupId` | 本机基础全量备份 ID |
| `baseBackupPath` | 本机基础全量备份路径 |

规则：

- 未加密全量导出成功后，更新基础备份 ID/路径；
- 加密全量导出不会成为基础备份；
- 增量导出只更新 last* 字段，不替换基础备份；
- wipe 清空全部备份元数据。

## 5. Diff 与恢复

### 5.1 生成 diff

以基础全量 `BackupDocument` 与当前全量快照逐表比较：

1. 当前行 ID 在基础中不存在：加入 changes；
2. 当前行 JSON 与基础不同：加入 changes；
3. 基础行 ID 在当前不存在：加入 deleted；
4. 附件元数据变化或首次出现：打包对应二进制；
5. 商户规则按 ID 做同样 diff；
6. summary 仍记录当前完整快照数量，供恢复预览使用。

### 5.2 合成完整快照

恢复增量文件时：

1. 读取本机 `baseBackupPath`；
2. 校验 base 文件非加密且 ID 与 `baseBackupId` 一致；
3. 从 base 的各表映射开始；
4. 执行 deleted 删除；
5. 用 delta changes upsert；
6. 合并附件元数据与二进制；
7. 生成普通 v2 全量 `BackupDocument`；
8. 后续 replace / merge 逻辑保持不变。

基础文件缺失、加密或 ID 不匹配时抛出明确的
`BackupFormatException`。

## 6. 自动备份与 UI

- `AutoBackupCoordinator` 调用 `exportToFile(incremental: true)`；
- 服务在无基础文件、基础文件损坏或用户选择加密时回退全量；
- 数据治理页增加“增量备份”复选项；
- 勾选加密时自动禁用增量并显示说明；
- 状态卡显示“增量备份”标签；
- Share 按钮仍分享最近文件；增量文件旁明确提示其依赖基础备份。

## 7. 实现清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `apps/client/lib/application/backup_service.dart` | diff、应用 delta、恢复合成、导出参数 |
| 2 | `apps/client/lib/application/backup_metadata_store.dart` | backupId / base path / incremental 元数据 |
| 3 | `apps/client/lib/platform/backup_file_port.dart` | `.ledgerly.inc.zip` 文件名与读写 |
| 4 | `apps/client/lib/application/auto_backup.dart` | 自动备份优先增量 |
| 5 | `apps/client/lib/presentation/pages/data_governance_page.dart` | 增量选项、状态提示 |
| 6 | `apps/client/lib/l10n/app_*.arb` | 新文案 |
| 7 | `apps/client/test/application/backup_service_incremental_test.dart` | 增删改、附件、基础缺失测试 |
| 8 | `apps/client/test/widget/data_governance_page_test.dart` | 增量开关与状态测试 |
| 9 | `docs/design/README.md` / `docs/roadmap/phases.md` | 文档与路线图 |

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 用户只分享增量文件，另一台设备无法恢复 | UI 明确“增量仅本机可恢复”，跨设备使用全量 |
| 基础文件被删除 | 导出/恢复检测失败并明确报错；导出自动回退全量 |
| 基础文件被加密 | 不把加密文件登记为 base；增量不可用 |
| diff 漏掉软删除 | transactions 以整行 JSON 对比，删除/更新都会进入 changes |
| 附件变化无法由元数据识别 | 附件当前设计不可变；新增附件进入增量，删除按 ID 记录 |
| 累积 diff 越来越大 | 下一次手工全量、加密全量或基础丢失都会建立新基础 |

## 9. 验收

- [x] 首次自动/手动增量导出在没有基础文件时回退全量；
- [x] 第二次导出只包含变更行、删除 ID 和变化附件；
- [x] 增量恢复后与导出时的全量快照一致；
- [x] 基础文件缺失时恢复给出明确错误；
- [x] 加密导出始终生成全量 `.enc.zip`；
- [x] 合成后的增量快照复用现有 replace / merge 引擎；
- [x] `flutter analyze` 无 issue；
- [x] `flutter test` 全量通过（380/380）。
