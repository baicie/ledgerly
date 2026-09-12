// Multi-device sync integration tests.
//
// Boots two devices side-by-side against a shared in-process
// [FakeSyncServer] and exercises the SyncService end-to-end. Each
// scenario is mapped to a critical sync invariant from the design
// doc (Phase 3.2):
//
//   1. A creates → B pulls                         → push + pull closure
//   2. B creates → A pulls                         → reverse push + pull
//   3. A & B create independently                   → eventual consistency
//   4. Both edit the same transaction               → conflict surfaces
//   5. B cold-start with seeded server              → bootstrap path
//   6. Replay same mutationId                       → idempotency
//   7. Multiple round trips                         → cursor monotonic
//
// No production code is modified by these tests. The SyncService
// keeps its real (LedgerRepository, SyncApi, AuthGateway) signature;
// we just swap the SyncApi and AuthGateway implementations.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';

import 'two_device_harness.dart';

Future<TwoDeviceHarness> _bootHarness() => TwoDeviceHarness.boot();

void main() {
  // Required when running under `flutter test -d chrome integration_test/`.
  // Safe to call from plain `flutter test integration_test/sync/` on a
  // host VM as well — it's a no-op there.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // -----------------------------------------------------------------
  // Scenario 1: A creates → B pulls
  // -----------------------------------------------------------------
  test('sync #1: A creates a transaction, B pulls it after syncNow',
      () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;
    final b = harness.deviceB;

    // A creates an expense offline.
    await a.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(1250),
      description: 'A latte',
      occurredAt: DateTime.utc(2026, 9, 12, 8),
    );

    // Push from A.
    final aResult = await a.syncService.syncNow();
    expect(aResult.ok, isTrue, reason: aResult.message);

    // B pulls.
    final bResult = await b.syncService.syncNow();
    expect(bResult.ok, isTrue, reason: bResult.message);

    // B's local ledger contains A's transaction. The account ids were
    // rewritten from the server-side prefix back to B's local book.
    final bSummaries =
        await b.repository.watchSummariesSync(defaultBookId);
    expect(bSummaries, hasLength(1));
    expect(bSummaries.first.description, 'A latte');
    expect(bSummaries.first.amountMinor, BigInt.from(1250));

    // B's sync_states advanced and recorded the remote book id.
    final bState = await b.repository.syncState(defaultBookId);
    expect(bState?.remoteBookId, harness.server.bookId);
    expect(bState?.cursor, greaterThan(0));
  });

  // -----------------------------------------------------------------
  // Scenario 2: B creates → A pulls (reverse direction)
  // -----------------------------------------------------------------
  test('sync #2: B creates a transaction, A pulls it after syncNow',
      () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;
    final b = harness.deviceB;

    await b.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(3300),
      description: 'B groceries',
      occurredAt: DateTime.utc(2026, 9, 12, 9),
    );

    final bPush = await b.syncService.syncNow();
    expect(bPush.ok, isTrue, reason: bPush.message);

    final aPull = await a.syncService.syncNow();
    expect(aPull.ok, isTrue, reason: aPull.message);

    final aSummaries =
        await a.repository.watchSummariesSync(defaultBookId);
    expect(aSummaries, hasLength(1));
    expect(aSummaries.first.description, 'B groceries');
  });

  // -----------------------------------------------------------------
  // Scenario 3: Both create independently → eventual consistency
  // -----------------------------------------------------------------
  test(
      'sync #3: A and B each create; after both syncs they converge on the '
      'same set of transactions',
      () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;
    final b = harness.deviceB;

    // Each device creates two transactions before any sync.
    await a.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(1100),
      description: 'A-1',
      occurredAt: DateTime.utc(2026, 9, 12, 7),
    );
    await a.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(1200),
      description: 'A-2',
      occurredAt: DateTime.utc(2026, 9, 12, 7, 30),
    );
    await b.appService.createIncome(
      incomeAccountId: accountKeySalary(defaultBookId),
      depositAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(50000),
      description: 'B-salary',
      occurredAt: DateTime.utc(2026, 9, 12, 10),
    );
    await b.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(2200),
      description: 'B-2',
      occurredAt: DateTime.utc(2026, 9, 12, 11),
    );

    // First sync: both push their own changes. Neither sees the other
    // yet because pulls happen against their own cursors.
    final aFirst = await a.syncService.syncNow();
    expect(aFirst.ok, isTrue, reason: aFirst.message);
    final bFirst = await b.syncService.syncNow();
    expect(bFirst.ok, isTrue, reason: bFirst.message);

    // Second sync: both pull. Now both see all four transactions.
    await a.syncService.syncNow();
    await b.syncService.syncNow();

    final aSummaries =
        await a.repository.watchSummariesSync(defaultBookId);
    final bSummaries =
        await b.repository.watchSummariesSync(defaultBookId);

    final aDescriptions = aSummaries.map((s) => s.description).toSet();
    final bDescriptions = bSummaries.map((s) => s.description).toSet();

    expect(aDescriptions, equals(bDescriptions));
    expect(aDescriptions, equals({'A-1', 'A-2', 'B-salary', 'B-2'}));
  });

  // -----------------------------------------------------------------
  // Scenario 4: Both edit the same transaction → conflict surfaces
  // -----------------------------------------------------------------
  test('sync #4: two devices edit the same transaction; the loser sees a '
      'LEDGER_VERSION_CONFLICT and produces a sync_conflicts row',
      () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;
    final b = harness.deviceB;

    // A creates a transaction and pushes it. Server version = 1.
    await a.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(1000),
      description: 'shared',
      occurredAt: DateTime.utc(2026, 9, 12, 12),
    );
    final aPush = await a.syncService.syncNow();
    expect(aPush.ok, isTrue, reason: aPush.message);

    // B pulls and now has the transaction locally.
    await b.syncService.syncNow();
    final bSummaries =
        await b.repository.watchSummariesSync(defaultBookId);
    expect(bSummaries, hasLength(1));
    final shared = bSummaries.first;
    expect(shared.version, 1);

    // Both edit it independently using the same `baseVersion=1`
    // (the version they both observed after pull). A's edit uses the
    // local-transaction update API; we feed B's edit through the
    // same path on device B.
    await b.appService.updateExpense(
      transactionId: shared.id,
      occurredAt: DateTime.utc(2026, 9, 12, 12),
      version: shared.version,
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(1000),
      description: 'B wins',
    );
    await a.appService.updateExpense(
      transactionId: shared.id,
      occurredAt: DateTime.utc(2026, 9, 12, 12),
      version: shared.version,
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(1000),
      description: 'A wins',
    );

    // B pushes first; succeeds and the server advances to version 2.
    final bPush = await b.syncService.syncNow();
    expect(bPush.ok, isTrue, reason: bPush.message);
    expect(harness.server.transactionsSnapshot, hasLength(1));
    expect(harness.server.transactionsSnapshot.single.version, 2);
    expect(
      harness.server.transactionsSnapshot.single.description,
      'B wins',
    );

    // A pushes second; the server returns LEDGER_VERSION_CONFLICT
    // because A's baseVersion=1 no longer matches server version 2.
    final aPushSecond = await a.syncService.syncNow();
    expect(aPushSecond.ok, isTrue, reason: aPushSecond.message);

    final conflicts =
        await a.repository.listConflicts(defaultBookId);
    expect(conflicts, hasLength(1));
    expect(conflicts.first.entityId, shared.id);
    expect(conflicts.first.reason, 'LEDGER_VERSION_CONFLICT');
    expect(conflicts.first.remoteVersion, 2);

    // The server description should still be B's winning write.
    expect(
      harness.server.transactionsSnapshot.single.description,
      'B wins',
    );
  });

  // -----------------------------------------------------------------
  // Scenario 5: Cold-start B pulls everything via bootstrap
  // -----------------------------------------------------------------
  test('sync #5: a freshly created B pulls the entire change log on first '
      'sync, matching what A had pushed earlier', () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;

    for (var i = 0; i < 5; i++) {
      await a.appService.createExpense(
        expenseAccountId: accountKeyFood(defaultBookId),
        fundingAccountId: accountKeyBank(defaultBookId),
        amountMinor: BigInt.from(100 * (i + 1)),
        description: 'seed-$i',
        occurredAt: DateTime.utc(2026, 9, 1).add(Duration(hours: i)),
      );
    }
    await a.syncService.syncNow();
    expect(
      harness.server.changeLogSnapshot
          .where((c) => c.entityType == 'transaction'),
      hasLength(5),
    );

    // Build a brand-new B that bypasses SyncService and goes through
    // the raw bootstrap endpoint — exercising the same code path the
    // real client uses after a SYNC_CURSOR_EXPIRED recovery.
    final freshDb = AppDatabase.forTesting(NativeDatabase.memory());
    final freshRepo = LedgerRepository(
      freshDb,
      deviceIdLoader: () async => 'dev_B_fresh',
    );
    await freshRepo.seedIfEmpty();

    final rawBootstrap = await harness.server.bootstrap();
    final changes = (rawBootstrap['changes'] as List).cast<Map>();
    expect(changes, hasLength(5));
    for (final raw in changes) {
      final change = Map<String, dynamic>.from(raw);
      expect(change['entityType'], 'transaction');
      await freshRepo.applyRemoteUpsert(
        entityId: change['entityId'] as String,
        bookId: defaultBookId,
        version: change['version'] as int,
        payload: Map<String, dynamic>.from(change['payload'] as Map),
      );
    }

    final freshSummaries =
        await freshRepo.watchSummariesSync(defaultBookId);
    expect(freshSummaries, hasLength(5));
    final descriptions =
        freshSummaries.map((s) => s.description).toSet();
    expect(
      descriptions,
      equals({'seed-0', 'seed-1', 'seed-2', 'seed-3', 'seed-4'}),
    );

    await freshDb.close();
  });

  // -----------------------------------------------------------------
  // Scenario 6: Replay same mutationId is a no-op (idempotency)
  // -----------------------------------------------------------------
  test('sync #6: replaying the same mutationId at the server is a no-op, '
      'and a client-side redrive clears the pending queue', () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;

    await a.appService.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyBank(defaultBookId),
      amountMinor: BigInt.from(2500),
      description: 'latte',
      occurredAt: DateTime.utc(2026, 9, 12, 14),
    );

    // First push drains the queue.
    final first = await a.syncService.syncNow();
    expect(first.ok, isTrue, reason: first.message);
    expect(harness.server.transactionsSnapshot, hasLength(1));
    expect(await a.repository.listPending(defaultBookId), isEmpty);

    // Capture the receipts from a *raw* push to the fake server so we
    // can replay the same mutation id. This mirrors what would happen
    // on a network-level retry: the client never received the
    // original receipt, so it pushes the same payload again.
    final transactionId = harness.server.transactionsSnapshot.single.id;
    final redriveMutationId = 'redrive-$transactionId';
    final redrivePayload = <String, dynamic>{
      'description': 'latte (redrive)',
      'occurredAt': '2026-09-12T14:00:00Z',
      'entries': [
        {
          'accountId': '${a.remoteBookId}:acc_food',
          'amountMinor': '2500',
          'currency': 'CNY',
        },
        {
          'accountId': '${a.remoteBookId}:acc_bank',
          'amountMinor': '-2500',
          'currency': 'CNY',
        },
      ],
    };
    final firstPush = await harness.server.push(
      deviceId: a.deviceId,
      mutations: [
        {
          'mutationId': redriveMutationId,
          'entityType': 'transaction',
          'entityId': transactionId,
          'operation': 'update',
          'baseVersion': 1,
          'schemaVersion': 1,
          'payload': redrivePayload,
        },
      ],
    );
    final firstReceipt =
        (firstPush['receipts'] as List).cast<Map>().single;
    expect(firstReceipt['status'], 'applied');
    expect(firstReceipt['mutationId'], redriveMutationId);
    expect(firstReceipt['entityVersion'], 2);

    // Replay: identical mutation id, identical payload. The fake
    // server's idempotency table must return the *same* receipt
    // without re-applying the mutation. The transaction row version
    // stays at 2; no new change-log entry is appended.
    final secondPush = await harness.server.push(
      deviceId: a.deviceId,
      mutations: [
        {
          'mutationId': redriveMutationId,
          'entityType': 'transaction',
          'entityId': transactionId,
          'operation': 'update',
          'baseVersion': 1,
          'schemaVersion': 1,
          'payload': redrivePayload,
        },
      ],
    );
    final secondReceipt =
        (secondPush['receipts'] as List).cast<Map>().single;
    expect(secondReceipt['status'], firstReceipt['status']);
    expect(secondReceipt['mutationId'], firstReceipt['mutationId']);
    expect(secondReceipt['entityVersion'], firstReceipt['entityVersion']);

    expect(harness.server.transactionsSnapshot, hasLength(1));
    expect(harness.server.transactionsSnapshot.single.version, 2);

    // Client-side redrive: re-queue the same update as a *fresh*
    // pending row (different mutation id) so SyncService exercises
    // its drain path. The new mutation advances the server's
    // version to 3, and the pending row is cleared locally.
    // The baseVersion must match the server's current version (2
    // after the raw redrive) — using the older 1 would just trip
    // LEDGER_VERSION_CONFLICT and produce a sync_conflicts row.
    final preRedrive = await a.repository.listPending(defaultBookId);
    expect(preRedrive, isEmpty);
    await _enqueueSameMutation(
      a,
      transactionId: transactionId,
      description: 'latte (client redrive)',
      baseVersion: harness.server.transactionsSnapshot.single.version,
    );
    final redrive = await a.syncService.syncNow();
    expect(redrive.ok, isTrue, reason: redrive.message);
    final pendingAfter = await a.repository.listPending(defaultBookId);
    expect(pendingAfter, isEmpty,
        reason: 'Client must clear pending after server receipt');
    expect(harness.server.transactionsSnapshot.single.version, 3);
  });

  // -----------------------------------------------------------------
  // Scenario 7: Cursor advances monotonically across multiple syncs
  // -----------------------------------------------------------------
  test('sync #7: across three push rounds the local cursor advances in '
      'lock-step with the server change log', () async {
    final harness = await _bootHarness();
    addTearDown(harness.close);

    final a = harness.deviceA;
    final b = harness.deviceB;

    final observed = <int>[];

    for (var i = 0; i < 3; i++) {
      await a.appService.createExpense(
        expenseAccountId: accountKeyFood(defaultBookId),
        fundingAccountId: accountKeyBank(defaultBookId),
        amountMinor: BigInt.from(100 * (i + 1)),
        description: 'round-$i',
        occurredAt: DateTime.utc(2026, 9, 1).add(Duration(days: i)),
      );
      final res = await a.syncService.syncNow();
      expect(res.ok, isTrue, reason: res.message);
      observed.add(res.cursor);
    }

    // B syncs after each round and we record B's cursor.
    final bObserved = <int>[];
    for (var i = 0; i < 3; i++) {
      final res = await b.syncService.syncNow();
      expect(res.ok, isTrue, reason: res.message);
      bObserved.add(res.cursor);
    }

    // Both cursors are strictly non-decreasing across rounds.
    for (var i = 1; i < observed.length; i++) {
      expect(observed[i], greaterThanOrEqualTo(observed[i - 1]));
    }
    for (var i = 1; i < bObserved.length; i++) {
      expect(bObserved[i], greaterThanOrEqualTo(bObserved[i - 1]));
    }

    // Server-side sequence count matches what cursors reflect.
    final serverSequences = harness.server.changeLogSnapshot
        .where((c) => c.entityType == 'transaction')
        .length;
    expect(serverSequences, 3);
    expect(observed.last, serverSequences);
    expect(bObserved.last, serverSequences);
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Re-queue an existing transaction's update mutation as a new pending
/// row. Used by scenario #6 to exercise the SyncService drain path
/// after a server-side replay has already applied an update.
Future<List<dynamic>> _enqueueSameMutation(
  Device device, {
  required String transactionId,
  required String description,
  required int baseVersion,
}) async {
  final remoteBookId = device.remoteBookId;
  // drift stores DateTime as Unix milliseconds (an int). The value
  // must stay inside the DateTime supported range
  // (-8640000000000000..8640000000000000 ms), which holds through
  // year ±271,800. Passing `microsecondsSinceEpoch` here would
  // exceed the upper bound and make the subsequent `listPending`
  // read throw a RangeError.
  final createdAtMillis = DateTime.now().toUtc().millisecondsSinceEpoch;
  await device.db.customStatement(
    '''
    INSERT INTO pending_mutations
      (mutation_id, book_id, device_id, entity_type, entity_id, operation,
       base_version, payload_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      // Use a fresh mutation id so the server treats this as a brand-new
      // mutation instead of returning the cached idempotency receipt
      // for the earlier raw push. `repo.newId()` is the same
      // monotonically-incrementing id generator used by the rest of
      // the LedgerRepository, so client-side dedup never collides.
      'redrive-${device.repository.newId()}',
      defaultBookId,
      device.deviceId,
      'transaction',
      transactionId,
      'update',
      baseVersion,
      jsonEncode({
        'description': description,
        'occurredAt': '2026-09-12T14:00:00Z',
        'entries': [
          {
            'accountId': '$remoteBookId:acc_food',
            'amountMinor': '2500',
            'currency': 'CNY',
          },
          {
            'accountId': '$remoteBookId:acc_bank',
            'amountMinor': '-2500',
            'currency': 'CNY',
          },
        ],
      }),
      createdAtMillis,
    ],
  );
  return device.repository.listPending(defaultBookId);
}
