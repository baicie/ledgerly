# Phase 3.1 设计：产品打磨

* 分支：随 `mvp/phase-2.5-real-sync` 一并落地
* 目标：可日常演示的移动端主路径

## 范围

- 月度流水筛选
- 交易软删除（Tombstone + pending delete mutation）
- 资产账户新建
- 冲突页读取真实 `sync_conflicts`
- 同步中心触发真实 Push/Pull

## 验收

- [x] 流水可按月切换
- [x] 删除后余额重算为 0（本地）
- [x] 可新建资产账户
- [x] 冲突来自本地表而非 demo 数据
