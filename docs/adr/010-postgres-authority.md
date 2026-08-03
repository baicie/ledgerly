# ADR-010：PostgreSQL 是云端权威收敛节点

* 状态：Accepted
* 日期：2026-08-03

## 决策

PostgreSQL 保存用户/设备/账本/账目/预算/同步日志/Receipt/冲突/订阅/导入任务。是多设备收敛权威、权限权威、云端备份权威，但不是 Flutter 页面直查数据源。

业务表显式 `book_id`；客户端对象 ID 使用 UUIDv7。RLS 可作纵深防御，不能替代应用层权限。
