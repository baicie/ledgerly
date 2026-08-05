# 复式记账核心数据模型

* Phase：0
* 参见：ADR-006、ADR-020

## 金额

```text
Money { minorUnits: BigInt, currency: CurrencyCode }
12.34 CNY → 1234
500 JPY   → 500
```

禁止 `double`。

## 实体

### Account

| 字段 | 说明 |
|------|------|
| id | AccountId |
| bookId | BookId |
| name | 显示名 |
| type | asset \| liability \| income \| expense \| equity |
| currency | CurrencyCode |
| parentAccountId | 可选父账户 ID；收支分类层级使用 |

### Transaction

| 字段 | 说明 |
|------|------|
| id | TransactionId |
| bookId | BookId |
| occurredAt | DateTime |
| description | 可选备注 |
| version | int ≥ 1 |
| entries | List\<TransactionEntry\> ≥ 2 |

### TransactionEntry

| 字段 | 说明 |
|------|------|
| id | EntryId |
| transactionId | 所属交易 |
| accountId | 账户 |
| amount | Money（非零） |
| index | 分录序号 |

## 收支分类层级

分类不是独立实体。`type=expense|income` 的 Account 同时承担收支分类职责，
TransactionEntry 继续直接引用实际记账的 Account。

`parentAccountId` 的语义：

| 值 | 含义 |
|----|------|
| `null` | 一级分类 |
| 同一账本中的 AccountId | 二级分类，指向所属一级分类 |

一级和二级分类都可以直接记账。层级只描述导航与展示关系，不改变分录归属。

### 层级不变量

1. 非空 `parentAccountId` 只用于 `income` 或 `expense` Account。
2. 父分类必须存在，且与子分类属于同一 Book、具有相同 `type`。
3. 父分类本身必须是一级分类，即父分类的 `parentAccountId == null`。
4. 分类不能以自身为父分类。
5. 已有二级分类的一级分类不能再改为二级分类。
6. 分类树最多两级，不允许第三级。

### 默认分类

默认清单共 36 个分类：12 个一级分类和 24 个二级分类。

| 类型 | 一级分类 | 二级分类 |
|------|----------|----------|
| 支出 | 餐饮 | 日常用餐、饮品零食 |
| 支出 | 交通 | 公交地铁、网约车、驾车养车 |
| 支出 | 购物 | 日用百货、服饰美妆、数码电器 |
| 支出 | 居住 | 房租房贷、水电燃气、物业家政 |
| 支出 | 休闲 | 娱乐、运动健身、旅行 |
| 支出 | 医疗健康 | 看病就医、药品保健 |
| 支出 | 学习 | 书籍、课程培训 |
| 支出 | 其他支出 | - |
| 收入 | 工资收入 | 基本工资、奖金 |
| 收入 | 副业收入 | 自由职业、经营收入 |
| 收入 | 投资收益 | 利息、分红 |
| 收入 | 其他收入 | - |

默认分类使用账本作用域内的稳定 AccountId。初始化和升级补齐都是幂等插入：
只创建缺失项，不覆盖用户已经修改的名称或层级。服务端数据库升级会为每个
现有 Book 补齐缺失项，并为实际插入的 Account 追加 Change Log，供其他设备
通过 Pull 收敛；Bootstrap 始终导出补齐后的完整账户集合。

## 交易不变量

1. `entries.length >= 2`
2. 同币种：`sum(amount.minorUnits) == 0`
3. 每条 `amount.minorUnits != 0`
4. 转账：两条分录同 `transactionId`，账户不同

## 余额

```text
balance(account) = SUM(entries where accountId = account)
```

余额是投影，不是独立事实。

## 报表与预算边界

当前报表和预算按实际选择的 AccountId 独立统计，不自动汇总一级分类的二级
分类。一级分类的余额只包含直接记到该一级分类的分录；二级分类的余额只包含
直接记到该二级分类的分录。界面可以显示“一级 / 二级”路径，但路径不改变
统计范围。若以后需要父级汇总，应作为显式投影能力设计，不能改写历史分录。
