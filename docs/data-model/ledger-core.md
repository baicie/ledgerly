# 复式记账核心数据模型

* Phase：0
* 参见：ADR-006

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

## 不变量

1. `entries.length >= 2`
2. 同币种：`sum(amount.minorUnits) == 0`
3. 每条 `amount.minorUnits != 0`
4. 转账：两条分录同 `transactionId`，账户不同

## 余额

```text
balance(account) = SUM(entries where accountId = account)
```

余额是投影，不是独立事实。
