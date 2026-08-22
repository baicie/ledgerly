# 设计：日常工具打磨（0.0.16）

* 分支：`feat/daily-tools-0.0.16`
* 状态：Implemented
* 日期：2026-08-23
* 相关：[local-daily-tools.md](./local-daily-tools.md)、ADR-011、ADR-014

## Objective

在 `v0.0.15` 日常工具之上，补齐每天都会碰到、且不依赖新后端的缺口，然后发 `v0.0.16`。

1. 账单导入更接近支付宝/微信真实导出
2. 周期记账支持月末，补齐时不重复入账
3. 报表页能看见本月分类预算进度
4. 流水附件能选图并预览
5. 应用锁在 PIN 之上可选生物识别
6. Android minSdk 24，并升级 `flutter_secure_storage` 11

成功标准：未启用锁时路径不变；PIN 仍是唯一回退；导入必须预览确认；附件二进制仍不进 Mutation。

## Product contract

| 能力 | 规则 |
|------|------|
| 导入 | UTF-8 / GBK；逗号 / Tab / 分号；跳过退款与关闭单；`交易对方` 作备注回退；已存在同日同额同备注的勾选取消；全选/全不选 |
| 周期 | 每月 1–31 日；该月没有这天则记在月末；补齐最多 36 笔；同规则同日同额同备注已存在则只推进下次日期 |
| 预算 | 报表页展示本月本地预算进度（含「全部支出」和子分类汇总） |
| 附件 | 流水可「添加图片」或「添加文件」；图片显示缩略图，点开预览；二进制仍只留本机 |
| 应用锁 | PIN 仍必填；启用后可开生物识别；冷启动/回前台先尝试生物识别，失败或取消则输入 PIN；Web / 无硬件时只显示 PIN |
| 安全存储 | minSdk 24；`flutter_secure_storage` 11。已在 v10 的数据先随 v10 迁移，再升 v11 |

不在本期：语音记账、拍照 OCR、家庭联合账本、服务端 `jsonwebtoken` / `rand` / `sha2` / `password-hash` 大版本。

## Architecture

```text
CSV bytes          → decodeBillCsvBytes (UTF-8 then GBK) → CsvBillParser
Import preview     → 预览勾选 + 账本去重标记
RecurringDate      → clamp to last day of month (1–31)
RecurringScheduler → catch-up skips already-posted rows, still advances
Reports            → localMonthBudgetProgressProvider
Attachments        → UserFilePort.pickBinaryFile(imagesOnly) + in-memory preview
App lock           → AppLockStore PIN + biometric flag; BiometricAuth port
Secure storage     → shared FlutterSecureStorage options
```

生物识别经 `BiometricAuth` 端口注入，测试用内存实现，避免 widget 测试依赖系统生物硬件。
