# ADR-002：Feature-first + MVVM + 轻量领域层

* 状态：Accepted
* 日期：2026-08-03

## 决策

四层架构：

```text
Presentation → Application → Domain
                    ↑
              Infrastructure
```

- Presentation：Widget、ViewModel、导航；禁止 SQL/同步/余额计算/拼装分录。
- Application：完整业务操作编排（领域校验、Repository、本地事务、pending mutation、同步触发）。
- Domain：纯业务规则，不依赖 Flutter/Riverpod/Drift/Dio。
- Infrastructure：Drift、Sync API、Secure Storage、平台能力。
