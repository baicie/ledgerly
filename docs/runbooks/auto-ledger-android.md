# 自动记账调试 Runbook

## 权限授予

### 手动（在设备上操作）

1. 打开设备「设置」→「应用」→ ledgerly
2. 找到「通知」或「特殊应用权限」→「通知访问」
3. 找到 Ledgerly，开启开关

### ADB 命令行（无需操作设备，适合 CI / 远程调试）

```bash
adb shell cmd notification allow_listener app.ledgerly.ledgerly_client/.PayNotificationListener
```

验证是否开启：

```bash
adb shell dumpsys notification --raw | grep "app.ledgerly.ledgerly_client"
```

输出包含 `ALLOW_LISTENERS` 则表示已授权。

## Logcat 查看捕获日志

```bash
adb logcat -s LedgerlyPay:V *:W
```

`LedgerlyPay` 是 `PayNotificationListener` 中定义的 TAG，正常捕获到通知时日志类似：

```
D LedgerlyPay: package=com.tencent.mm
    title=微信支付
    text=向美团外卖付款28.50元
    bigText=
```

未看到任何日志 → 检查权限是否授予。

## 验证解析结果

打开 App → 设置 → 自动记账，查看「待处理事件」列表。

列表为空但 Logcat 有日志 → 检查 `PaymentEventStore` 是否持久化成功：

```bash
adb shell dumpsys SharedPrefs app.ledgerly.ledgerly_client
# 查找 key=ledgerly_payment_events
```

## 跑 Kotlin 单元测试（无需设备）

```bash
cd apps/client/android
./gradlew :app:testDebugUnitTest --tests "app.ledgerly.ledgerly_client.PaymentParserTest"
```

## 清除队列（重置测试状态）

### 方法一：App 内

设置 → 自动记账 → 页面内应有「清除队列」操作。

### 方法二：ADB

```bash
# 直接清除 SharedPreferences
adb shell "run-as app.ledgerly.ledgerly_client \
  pm clear app.ledgerly.ledgerly_client || \
  cat /data/data/app.ledgerly.ledgerly_client/shared_prefs/ledgerly_payment_events.xml"
```

### 方法三：Flutter 测试中

在测试代码里调用 `PaymentNotificationService` 的 fake 实现，`when(...).thenAnswer(...)` 返回空列表即可。

## 常见问题

| 现象 | 原因 | 解法 |
|------|------|------|
| Logcat 无日志，微信有通知 | 未授权通知访问 | ADB 授权或手动开启 |
| 列表有事件但未入账 | Flutter 引擎未启动（App 冷启） | 打开 App 触发同步 |
| 金额解析为 0 | 正则未匹配到金额格式 | 检查 `PaymentParser.AMOUNT_PATTERNS`，对照实际通知文案 |
| 商户名为空 | 商户正则未覆盖该通知格式 | 对照日志中 `title/text/bigText` 字段，更新 `MERCHANT_PATTERNS` |
| 重复入账 | 去重正则窗口内再次触发 | 确认 60s 内未重复点击；检查 Ledger 中是否有同金额同商户记录 |
| App 后台被杀后通知丢失 | 系统回收 NotificationListenerService | 正常现象，`PaymentEventStore` 持久化已解决；被杀前捕获的仍会入队 |

## 通知文案变更追踪

微信/支付宝每次版本更新可能改变通知标题和正文格式。解析失败时：

1. 拉取新版本 App 的通知
2. 记录 `adb logcat -s LedgerlyPay` 中的 `title=` / `text=` / `bigText=`
3. 更新 `PaymentParser` 中的 `AMOUNT_PATTERNS` 或 `MERCHANT_PATTERNS`
4. 在 `PaymentParserTest` 中补充对应 case
5. `./gradlew :app:testDebugUnitTest` 确认回归
