# ADR-BE-006：代码优先 OpenAPI

* 状态：Accepted
* 日期：2026-08-03

## 决策

utoipa 从 Rust DTO 生成 OpenAPI。分离 Request/Response DTO、Command、Domain、Row、Sync Payload。统一错误 `{code,message,requestId,details}`；客户端只依赖 `code`。
