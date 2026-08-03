# ADR-BE-018：低资源部署配置

* 状态：Accepted
* 日期：2026-08-03

## 决策

2vCPU/4GiB。Tokio worker_threads=2 起步。有界 Channel；Sync batch 限量；流式解析；CPU 密集走 spawn_blocking。空闲 RSS 工程目标 ≤64MiB。
