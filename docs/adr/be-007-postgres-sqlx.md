# ADR-BE-007：PostgreSQL + SQLx + 显式 SQL

* 状态：Accepted
* 日期：2026-08-03

## 决策

不用重 ORM。共享单一 PgPool。同进程初始：min=1 max=8；分开时 API max=5、Worker max=3。禁止长事务持连接、事务内外部 HTTP、大文件解析持连接。
