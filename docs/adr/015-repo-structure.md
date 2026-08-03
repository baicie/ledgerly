# ADR-015：代码仓库结构

* 状态：Accepted
* 日期：2026-08-03

## 决策

单主仓：

```text
apps/client/          # Flutter
server/               # Rust workspace
packages/             # Dart packages
infrastructure/
docs/
```

Dart 用 Pub Workspace；Rust 用 Cargo Workspace。不强行统一包管理器。
