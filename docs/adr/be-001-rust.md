# ADR-BE-001：选择 Rust

* 状态：Accepted
* 日期：2026-08-03

## 决策

主后端语言：Rust。

优先级：数据正确性 > 低资源占用 > 运行稳定性 > 开发速度。

不选 Go（GC/空闲内存）、Node（V8 Heap）、Spring/JVM（常驻内存）。若团队主熟悉 Go 且迭代变为运营 CRUD 主导，可重评。
