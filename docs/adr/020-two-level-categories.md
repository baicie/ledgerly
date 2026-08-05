# ADR-020：用 Account 自引用表达两级收支分类

* 状态：Accepted
* 日期：2026-08-05
* 参见：[ADR-006](./006-double-entry.md)、[ADR-007](./007-sync-protocol.md)、[ADR-018](./018-release-compatibility.md)

## Context

Ledgerly 已将收入和支出分类建模为 Account，TransactionEntry 直接引用实际
记账账户。产品需要更完整的默认分类、最多两级的分类导航和分类编辑能力，同时
必须保留历史分录引用，并兼容尚不认识层级字段的旧客户端。

如果另建 Category 实体，就需要在 Category 与 Account 之间维护一对一映射，
并迁移所有交易、预算和同步引用。任意深度分类树则会增加移动、删除、查询和
冲突处理的复杂度，超出当前个人记账场景的需要。

## Decision

继续使用 `type=income|expense` 的 Account 表达分类，并在 Account 上增加可空
的自引用 `parentAccountId`：

- `parentAccountId == null` 表示一级分类。
- 非空表示二级分类，并指向同一 Book、同一 Account type 的一级分类。
- 父分类必须存在且没有父分类；禁止自引用和第三级。
- 已有子分类的一级分类不能改为二级分类。
- 一级和二级分类都可以直接承载 TransactionEntry，以保留历史行为。

层级约束由客户端领域服务和服务端 Mutation 处理共同校验。服务端拒绝非法
父级时返回 `INVALID_CATEGORY_PARENT`。PostgreSQL 模式在同一 Book 内串行执行
Account 层级校验和写入，防止两个并发 Mutation 分别通过校验后形成循环或第
三级。

同步协议对 `parentAccountId` 使用三态语义：

- 字段缺省：`create` 时按一级分类处理，`update` 时保留现有父级。
- 显式 `null`：设置为一级分类。
- AccountId 字符串：设置或更换父级。

字段缺省与显式 `null` 不得合并处理，这是旧客户端编辑二级分类时不破坏层级
的兼容边界。服务端 canonical Change、Pull 和 Bootstrap 始终返回该字段。
客户端收到 `INVALID_CATEGORY_PARENT` 后将本地分类提升为一级，并用新的
mutation ID 最多重试一次；远端父级字段类型异常时中止 Pull 且不推进 cursor。

默认清单固定为 12 个一级分类和 24 个二级分类。客户端初始化、客户端数据库
升级和服务端数据库升级均按稳定 AccountId 幂等补齐，只插入缺失项，不覆盖
用户已有修改。服务端为升级实际插入的默认分类记录 Change Log。

报表与预算当前按实际 AccountId 统计，不自动把二级分类汇总到一级分类。父级
汇总若未来需要，将作为显式投影能力另行设计。

## Alternatives Considered

### 独立 Category 实体

需要维护 Category 到 Account 的映射，并迁移交易、预算和同步协议中的现有
AccountId 引用。它没有为当前两级需求提供足够收益，因此不采用。

### 任意深度分类树

能够提供更灵活的组织方式，但会放大移动子树、循环检测、删除语义、聚合查询
和同步冲突的复杂度。当前产品只需要两级，因此不采用。

### 一级分类仅作为不可记账的分组

模型更纯粹，但会使已有一级分类上的历史分录失去合法归属，也增加迁移和编辑
限制，因此一级、二级都保持可记账。

### 一级分类自动汇总二级分类

父级也可直接记账时，自动汇总会引入预算范围和报表口径的新语义。当前先保持
按实际账户统计，避免在层级上线时同时改变财务结果。

## Consequences

- 现有 TransactionEntry 和 AccountId 保持不变，数据库变更是可空列的扩展。
- 展示层需要解析父级路径，写入层必须在客户端和服务端执行同样的两级校验。
- 旧客户端仍可把分类当作平面列表使用；其更新不会因字段缺省而清空父级。
- 默认分类补齐可重复执行，并保留用户对既有分类的名称和层级修改。
- 一级汇总不是当前余额、报表或预算的隐含行为。
