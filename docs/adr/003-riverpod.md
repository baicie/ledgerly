# ADR-003：Riverpod 仅负责依赖管理和响应式状态

* 状态：Accepted
* 日期：2026-08-03

## 决策

Riverpod 管理注入、ViewModel 生命周期、当前账本、查询条件、异步/同步/登录状态。

禁止仅保存在 Provider 中：交易、账户、分类、预算、pending mutation、游标、冲突、设备记录。

第一阶段：Drift/json_serializable 用代码生成；Riverpod 优先手写 Provider。
