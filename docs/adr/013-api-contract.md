# ADR-013：API 契约与版本演进

* 状态：Accepted
* 日期：2026-08-03

## 决策

服务端以 Rust DTO + utoipa 生成 OpenAPI；生成 Dart Client。分离 Row / Domain / API DTO / Sync Payload / UI State。兼容：新增可选字段；不重命名已发布字段；金额单位不变；至少兼容近两个主客户端版本。
