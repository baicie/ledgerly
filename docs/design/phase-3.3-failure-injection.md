# Phase 3.3 设计：失败注入与重试路径

* 分支：`feat/phase-3.3-failure-injection`（在 Phase 3.2 之上）
* 状态：Implemented
* 日期：2026-09-13
* 前置：[phase-3.2-multi-device-sync-integration.md](./phase-3.2-multi-device-sync-integration.md)

## Objective

把 Phase 3.2 留出的 `FakeSyncServer` 失败注入钩子（`failNextPush` /
`dropNextChange` / `forceLedgerVersionConflict` / `resetCursorFor`）从
"API 已就位，无场景验证"推到"行为有断言守住"，覆盖客户端在 push /
pull 两条线上的失败-恢复路径。

成功标准：

1. 新增 `sync #8`、`sync #9` 两个集成场景，CI 集成 job 全绿。
2. 修复 `FakeSyncServer.pull` 在 `dropNextChange` 时的 cursor 回归 bug。
3. 不修改生产代码（与 Phase 3.2 同口径）。

## 现状与缺口

| 层 | 现状 | 缺口 |
|----|------|------|
| Phase 3.2 `multi_device_sync_test.dart` | 覆盖 #1–#7 happy path | 无 push 失败 / pull 丢笔的负面路径 |
| `FakeSyncServer.failNextPush` | API 就位，抛 `StateError` | 无场景验证 `sync_states.last_error` 落库、pending 不丢 |
| `FakeSyncServer.dropNextChange` | API 就位，page 末项被剔除 | **cursor 用了原 page 的末项而非实际返回，导致被丢的 change 永久丢失** |
| 生产 SyncService | 已捕获任意异常并写入 `last_error` | 未被自动化测试覆盖 |

第 3 行是隐性 bug：客户端拿到 `nextCursor = 3`（假定拿到 change #3），但
实际只收到 #1 / #2。下一次 pull 会跳过 #3 直接要 #4，#3 在 B 端永远缺席。
本次连带修掉。

## 范围

### In-scope

- `FakeSyncServer.pull`：`nextSequence` 改用 `pageChanges.last.sequence`
- 新增场景 #8：服务端 push 一次性失败，验证 SyncService 报告失败、保留
  pending、写入 `last_error`；恢复后再 syncNow 必须 drain
- 新增场景 #9：服务端 pull 一次性丢最后一笔，验证 cursor 不会跳过被丢的
  change；下一轮 pull 必须把缺口补齐
- 测试顶部场景清单同步更新

### Out-of-scope

- `forceLedgerVersionConflict` 已在 Phase 3.2 #4 通过服务端"真"路径覆盖，
  本次不重复
- `resetCursorFor` 涉及 `SYNC_CURSOR_EXPIRED` + bootstrap 路径，那是
  SyncService 的功能缺口（生产 `syncNow` 只调 `pull`，不调 `bootstrap`），
  留到 Phase 3.4 单独设计
- 服务端侧的连接重试 / 指数退避：fake server 是同步调用，不存在；真实
  server 走 Postgres + Dio，行为不在本测试范围

## 修复点详解

### `FakeSyncServer.pull` 的 cursor 回归

```diff
-    final nextSequence =
-        page.isEmpty ? effectiveCursor : page.last.sequence;
+    final nextSequence =
+        pageChanges.isEmpty ? effectiveCursor : pageChanges.last.sequence;
```

`page` 是原始待发列表，`pageChanges` 是实际返回的列表（`dropNextChange`
触发时是 `page` 去掉末项）。`nextCursor` 必须反映客户端**实际收到**的
序列号，否则 cursor 会跨过被丢的 change。

## 场景矩阵

| # | 场景 | 期望 |
|---|------|------|
| 8 | **push 一次性失败** | 第一次 `syncNow` 返回 `ok=false`、message 含 `injected push failure`、`pendingCount=1`、`sync_states.last_error` 非空、cursor 不前进、服务端无事务；去掉失败注入后第二次 `syncNow` 返回 `ok=true`、`pendingCount=0`、服务端 1 笔、`last_error` 被清 |
| 9 | **pull 丢最后一笔** | B 已经拉到 cursor=2；A 新建并 push 第 3 笔；服务端 `dropNextChange` 后 B 的 `syncNow` 返回 `ok=true`、cursor=2（不前进）、本地仍只有 2 笔；下一轮 `syncNow` 拿到第 3 笔、cursor=3、本地 3 笔；服务端 change log 始终保留全部 3 笔 |

## 风险

| 风险 | 缓解 |
|------|------|
| `failNextPush` 抛 `StateError` 与真 DioException 不同 | SyncService 是泛型 `catch (e)`，任意异常都会落到 `last_error`；这正是要测的路径 |
| 测试只在 happy-then-recovery 一来一回做断言，未覆盖多次连续失败 | 单次失败已够覆盖"SyncService 不丢 pending"这条不变量；多次失败的合并场景留到 Phase 3.4 |
| `dropNextChange` 修在 fake server 上，真 server 行为如何 | `server/src/transport/sync.rs::pull_book` 的真实 cursor 推进来自 SQL `WHERE seq > $cursor ORDER BY seq` 加 `last_value(seq)`，行为与修复后的 fake 一致 |

## Commands

```bash
cd apps/client

# Linux / macOS host VM（Windows 需要 Developer Mode 或预 build web）
flutter test integration_test/sync/

# CI 路径
flutter test -d chrome integration_test
```

## Success criteria

- [x] `FakeSyncServer.pull` cursor 回归修复，#9 验证 cursor 不跳过被丢的 change
- [x] `sync #8`：`failNextPush` 下 syncNow 行为正确
- [x] `sync #9`：`dropNextChange` 下 cursor 回落 + 下一轮补齐
- [x] `flutter analyze integration_test/sync/` 无 issue
- [x] 9 个场景全绿
- [x] CI 集成 job 自动覆盖

## 不在本次范围

- `forceLedgerVersionConflict` 显式调用：Phase 3.2 #4 已通过真实冲突路径覆盖
- `resetCursorFor` 触发 bootstrap 路径：留 Phase 3.4
- push 失败后的指数退避 / 客户端重试调度：留 Phase 3.4
