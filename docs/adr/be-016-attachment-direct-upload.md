# ADR-BE-016：附件直传对象存储

* 状态：Accepted
* 日期：2026-08-03

## 决策

签名 URL 直传；不信任客户端 MIME；服务端生成 object key；Worker 校验并缩略图。本轮 MVP 可延后实现。
