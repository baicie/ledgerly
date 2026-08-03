# Ledgerly 文档索引

阅读顺序建议：

1. [CONTEXT.md](./CONTEXT.md) — 产品定位、术语、核心不变量
2. [roadmap/mvp.md](./roadmap/mvp.md) — 本轮 MVP 目标与验收
3. [roadmap/phases.md](./roadmap/phases.md) — 全阶段路线图
4. [adr/index.md](./adr/index.md) — 架构决策记录
5. [design/](./design/) — 各阶段设计（实现前必须完成）
6. [data-model/](./data-model/) — 数据模型
7. [sync-protocol/](./sync-protocol/) — 同步协议

## 工作流

每个实现阶段强制：

```text
设计文档 → ADR（如有新决策）→ 阶段分支实现 → 验收 → 合并 main
```

未完成对应 `docs/design/phase-*.md` 前，不得开始业务代码。

## 仓库结构（目标）

```text
ledgerly/
├── apps/client/      # Flutter
├── server/           # Rust + Axum
├── packages/         # Dart packages
├── docs/
└── infrastructure/
```
