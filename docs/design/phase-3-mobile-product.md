# Phase 3 设计：移动端产品 MVP

* 分支：`mvp/phase-3-mobile-product`
* ADR：012、008

## 信息架构

```text
BottomNav
├── 流水 HomeFeed
├── 资产 Accounts
├── 报表 Reports
└── 我的 Settings
      ├── 同步中心 SyncCenter
      ├── 冲突 Conflicts
      ├── 应用锁 AppLock
      └── 导出 ExportCsv
```

快速记账：FAB → QuickEntrySheet（支出/收入/转账）。

## 验收

- [x] 主路径可演示：列表 + 快速记账
- [x] 资产余额由分录聚合展示
- [x] 分类报表页面存在
- [x] 同步中心与冲突页可进入
- [x] 最小 CSV 导出
