# Phase 3.2 设计：多设备同步集成测试

* 分支：`mvp/phase-3.2-sync-integration`（暂存）
* 状态：Implemented
* 日期：2026-09-12
* 相关：[phase-3-mobile-product.md](./phase-3-mobile-product.md)、[phase-3.1-product-polish.md](./phase-3.1-product-polish.md)、[phase-2-sync-loop.md](./phase-2-sync-loop.md)、ADR-007 / ADR-008 / BE-009 / BE-010

## Objective

把客户端 `SyncService` 的关键不变量用自动化测试守住，覆盖 Phase 0~3 中**没有 e2e 覆盖**的最高风险面：

1. **Push 闭环**：本地 Mutation 出队 → 服务端记账 → Receipt 回执 → 本地清 pending
2. **Pull 闭环**：服务端 Change Log 拉取 → 账户 ID 反向重写 → 本地 Drift 落库
3. **双向收敛**：A、B 各自创建交易后，最终彼此看见对方的全部数据
4. **冲突建模**：双方改同一交易，客户端产生可解决的 conflict 行
5. **Bootstrap**：B 首次启动从服务端拉回完整账本快照
6. **幂等**：同一 `mutationId` 重发不会重复入账
7. **Cursor 一致性**：服务端 cursor 与本地 `sync_states.cursor` 同步推进

成功标准：所有 7 个场景在 `flutter test integration_test/sync/` 下绿；
CI `integration` job 在 Chrome 上同步跑通；改动不修改 `SyncService` 业务代码。

## 现状与缺口

| 层 | 现有覆盖 | 缺口 |
|----|----------|------|
| 服务端单边 | `server/tests/postgres_flow.rs`（含 Push/Pull/Conflict 集成） | 客户端代码路径是否真的正确调用没有校验 |
| 客户端单元 | `apps/client/test/sync_api_test.dart`（Mock Dio 解析） | 不验真实 LedgerRepository 读写 |
| 客户端 Widget | `integration_test/app_test.dart` + `journey_test.dart` | 全部本地模式，零网络 |
| **多设备 e2e** | **无** | **本次填补** |

客户端 `SyncService` 经过多次重构（账户 ID 重写、Category 父级重试、Receipt `resultCode` 路由），每条路径都缺一次往返校验。

## 范围

### In-scope

- 进程内共享 `FakeSyncServer`，按真实服务端契约返回
- `FakeSyncApi`：继承 `SyncApi`，覆盖 `push / pull / bootstrap` 三个同步方法，其余委托 `NoopDio`
- `TwoDeviceHarness`：组装两个设备（A、B），每个设备拥有独立 in-memory Drift DB，共享一个 FakeSyncServer
- `FakeAuthGateway`：固定 `bookId`、设备 id、refresh token，避免真鉴权
- 7 个集成场景（见下表）

### Out-of-scope

- 真 Postgres、真 server、真 Refresh Token 旋转
- 商业化 API（invites / budgets / attachments / fx-rates / reports）
- WebSocket 唤醒（BE-015）
- Cursor 单调性服务端侧校验（postgres_flow.rs 已覆盖）
- 商业化表 `subscriptions` / `fx_rates`

## 架构

```text
TwoDeviceHarness
  ├─ Device A
  │   ├─ AppDatabase (NativeDatabase.memory)            ─┐
  │   ├─ LedgerRepository                              ─┤ 独立 DB
  │   ├─ SyncService                                   ─┘
  │   ├─ FakeAuthGateway (bookIdA, deviceIdA)  ──┐
  │   └─ FakeSyncApi ── routes push/pull ────────┤
  │                                              │
  ├─ Device B                                     │ 共享 server
  │   ├─ AppDatabase (NativeDatabase.memory)      │
  │   ├─ LedgerRepository                        ─┤
  │   ├─ SyncService                              │
  │   ├─ FakeAuthGateway (bookIdB, deviceIdB) ────┤
  │   └─ FakeSyncApi ─────────────────────────────┤
  │                                              ▼
  └─ FakeSyncServer (singleton)
      ├─ accountsByRemoteBook: Map<bookId, Map<accountId, payload>>
      ├─ changeLog: List<{entityType, entityId, op, version, payload}>
      ├─ pendingMutations: Map<bookId, List<{mutationId, ...}>>
      ├─ devices: Map<deviceId, cursor>
      └─ scenarios:
          ├─ resetCursor()      ── 测试 cursor 重置
          ├─ dropNextChange()   ── 测试拉取丢失
          └─ failNextPush()     ── 测试重试路径
```

### 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| Fake API 形态 | 继承 `SyncApi`，override push/pull/bootstrap | `SyncApi` 未声明为 `final`；不引入新接口减少噪音；其余 `dio` 字段全无用（Dio 不会真发请求） |
| 服务端数据形态 | 进程内 Map + List | 不引入真实 Postgres/Tokio，CI 在 Linux / Chrome / Windows 都能跑 |
| 设备标识 | FakeAuthGateway 直接返回固定 `(bookId, deviceId, plan)` | 绕过真鉴权；`bookIdA == bookIdB` 模拟同一账本多设备 |
| Account ID 跨端 | 服务端存远端 `accountId`；客户端走 `_rewriteAccountId` 重写 | 与真实实现一致，不绕开 `SyncService._rewriteAccountId` 这条关键路径 |
| Conflict 触发 | FakeSyncServer 在 `baseVersion` 不匹配时返回 `LEDGER_VERSION_CONFLICT` | 复用客户端既有 conflict 处理分支 |
| Idempotency 触发 | FakeSyncServer 用 `mutationId` 去重；同 id 重发返回原 receipt | 与 server `mutations.mutation_id` unique 约束一致 |
| Bootstrap 触发 | FakeSyncServer 在 `bootstrap` 调用时返回完整 change log（无视 cursor） | 客户端 `SyncService.syncNow` 不直接调 bootstrap，所以场景单独写一个 bootstrap 路径，绕开 SyncService |
| 失败注入 | `FakeSyncServer` 暴露 `failNextPush / dropNextChange / resetCursor` | 覆盖 retry / resilience 路径 |

### SyncService 不改

本次只新增 `apps/client/integration_test/sync/**` 与 `docs/**`，**不修改任何生产代码**。
理由：

- `SyncService` 已经是 `(LedgerRepository, SyncApi, AuthGateway)` 依赖注入形态
- 现有 widget 测试已经在 override `SyncApi`（虽未直接覆盖），证明该路径可注入
- 改生产代码会模糊"测试本身"和"实现修改"两类问题，违反"先测试后实现"

## 场景矩阵

| # | 场景 | 期望 |
|---|------|------|
| 1 | **A 创建 → B 拉取** | A `service.createExpense` 后 `syncNow`；B `syncNow` 后 `repo.watchSummaries` 包含 A 的交易，账户 ID 已重写为 B 端 `book_default:...` 形态 |
| 2 | **B 创建 → A 拉取** | 同 1，方向反过来 |
| 3 | **双方创建 → 彼此同步** | A、B 各自新建交易；各 `syncNow` 一次；两台设备 `watchSummaries` 数量和金额一致 |
| 4 | **冲突建模** | A、B 同时改同一交易（不同 `baseVersion`）；B 后 push → receipt `LEDGER_VERSION_CONFLICT` → `repo.listConflicts` 返回 1 行 |
| 5 | **Bootstrap** | 设备 B 在 A 已经 push 5 笔后首次启动；调用 fake bootstrap 路径（绕过 SyncService）拿到全部 5 笔 |
| 6 | **幂等** | 同一 `mutationId` 连续 push 两次；服务端只入账一次；第二次 receipt `status=applied` 但 pending 不重新入队 |
| 7 | **Cursor 推进** | A、B 各 `syncNow` 三轮；本地 `sync_states.cursor` 与 fake server 的 `nextCursor` 单调递增 |

## 边界

- **Always**：
  - 不改 `SyncService` / `LedgerRepository` / `SyncApi` 业务代码
  - 不引入 Postgres / Redis / 网络端口
  - 测试在 `flutter test integration_test/sync/` 下能跑，不需要真设备
  - FakeSyncServer 状态在每个 `setUp` 重置
- **Ask first**：把 FakeSyncServer 提升成生产可复用的"集成测试 server"；增加 WebSocket 唤醒模拟
- **Never**：把测试 server 暴露在 `lib/` 下；用 mockito / mocktail 等重型库（保持轻量、显式）

## 测试结构

```text
apps/client/integration_test/sync/
├── README.md                          # 运行说明
├── fake_sync_server.dart              # 进程内服务端，存储 + 失败注入
├── fake_sync_api.dart                 # SyncApi 子类，路由到 server
├── fake_auth_gateway.dart             # AuthGateway 实现
├── two_device_harness.dart            # 装配两设备 + 共享 server
└── multi_device_sync_test.dart        # 7 个 testWidgets / test 场景

apps/client/integration_test/
├── app_test.dart                      # 已存在（不动）
└── journey_test.dart                  # 已存在（不动，本阶段一并提交）
```

## Commands

```bash
# 本地（host VM / 桌面）
cd apps/client
flutter test integration_test/sync/

# Web（CI 路径）
flutter test -d chrome integration_test/sync/
```

## CI 接线

`.github/workflows/ci.yml` 的 `integration` job 改为：

```yaml
- name: Run integration tests
  run: |
    cd apps/client
    flutter test -d chrome integration_test/
```

（`flutter test integration_test/` 会跑目录下所有 `*_test.dart`，自然包含 `sync/` 子目录）

## 风险

| 风险 | 缓解 |
|------|------|
| `SyncApi` 是具体类，Dio 字段非 null 难造 | Dio 用 `Dio()` 即可，从不发请求；不校验 baseUrl |
| Account ID 重写在跨端后出错 | 测试同时校验 `remoteBookId` 在 sync_states 中落库，且拉取的 entity 已重写回本地 bookId 前缀 |
| `SyncService.syncNow` 入口固定 `defaultBookId`，多账本分支未覆盖 | 本期仅覆盖单账本；多账本场景留到 Phase 4 之后的 e2e |
| FakeSyncServer 行为偏离真 server | 限制 fake 实现只覆盖本次 7 个场景所需行为；后续 postgres_flow.rs 仍是真契约 |

## Success criteria

- [x] `docs/design/phase-3.2-multi-device-sync-integration.md` 入库
- [x] `apps/client/integration_test/sync/` 完整落地
- [x] `dart analyze integration_test/sync/` 无 issue
- [x] 7 个场景至少在 `flutter test -d chrome integration_test/sync/` 下绿
- [x] `flutter test integration_test/`（含 `app_test.dart` + `journey_test.dart`）不退化
- [x] ci.yml `integration` job 自动跑新测试

## 不在本次范围

- 客户端多账本同步（feature/multi-books 之前的探索，本期不重做）
- 离线 → 上线 → 增量 Pull 的真实网络抖动模拟（fake server 已留 `dropNextChange` 钩子，二期使用）
- Push 失败回滚（fake server `failNextPush` 二期使用）
- 服务端变更日志压缩（`compact_sync_log` Job）
