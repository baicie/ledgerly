import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/sync_service.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/sync_api.dart';
import 'package:ledgerly_client/domain/ids.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  test('offline create expense enqueues pending mutation and updates balance',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);

    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(3000),
      description: 'Lunch',
    );

    final summaries = await repo.watchSummariesSync(defaultBookId);
    expect(summaries, hasLength(1));
    expect(
      await repo.accountBalance(accountKeyFood(defaultBookId)),
      BigInt.from(3000),
    );
    expect(
      await repo.accountBalance(accountKeyCash(defaultBookId)),
      BigInt.from(-3000),
    );

    final pending = await repo.listPending(defaultBookId);
    expect(pending, hasLength(1));
    expect(pending.first.operation, 'create');
    expect(pending.first.deviceId, 'test-device');
  });

  test('offline create expense preserves an explicitly selected date',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'backfill-date-device',
    );
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);
    final occurredAt = DateTime.utc(2024, 4, 13, 12, 34, 56);

    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(1800),
      description: 'Forgotten lunch',
      occurredAt: occurredAt,
    );

    final summary = (await repo.watchSummariesSync(defaultBookId)).single;
    expect(summary.occurredAt.toUtc(), occurredAt);
    final pending = (await repo.listPending(defaultBookId)).single;
    final payload = jsonDecode(pending.payloadJson) as Map<String, dynamic>;
    expect(payload['occurredAt'], occurredAt.toIso8601String());
  });

  test('remote upserts normalize dates and legacy updates preserve them',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'remote-date-device',
    );
    await repo.seedIfEmpty();
    final entries = [
      {
        'accountId': accountKeyFood(defaultBookId),
        'amountMinor': '1800',
        'currency': 'CNY',
      },
      {
        'accountId': accountKeyCash(defaultBookId),
        'amountMinor': '-1800',
        'currency': 'CNY',
      },
    ];

    await repo.applyRemoteUpsert(
      entityId: 'remote-date-transaction',
      bookId: defaultBookId,
      version: 1,
      payload: {
        'description': 'Forgotten lunch',
        'occurredAt': '2024-04-13T12:34:56+08:00',
        'entries': entries,
      },
    );
    await repo.applyRemoteUpsert(
      entityId: 'remote-date-transaction',
      bookId: defaultBookId,
      version: 2,
      payload: {
        'description': 'Updated lunch',
        'entries': entries,
      },
    );

    final summary = (await repo.watchSummariesSync(defaultBookId)).single;
    expect(
      summary.occurredAt.toUtc(),
      DateTime.utc(2024, 4, 13, 4, 34, 56),
    );
    expect(summary.description, 'Updated lunch');
  });

  test('remote upsert rejects non-RFC 3339 occurred dates', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'invalid-remote-date-device',
    );
    await repo.seedIfEmpty();

    for (final invalidDate in [
      'not-a-date',
      '2024-04-13',
      '2024-04-13T12:34:56',
      '2024-02-30T12:34:56Z',
    ]) {
      await expectLater(
        repo.applyRemoteUpsert(
          entityId: 'invalid-date-transaction',
          bookId: defaultBookId,
          version: 1,
          payload: {
            'description': 'Invalid date',
            'occurredAt': invalidDate,
            'entries': const [],
          },
        ),
        throwsFormatException,
        reason: invalidDate,
      );
    }
  });

  test('transaction summaries expose the amount, category, and account',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);

    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(4280),
      description: 'Dinner',
    );

    final summary = (await repo.watchSummariesSync(defaultBookId)).single;
    expect(summary.kind, TransactionSummaryKind.expense);
    expect(summary.amountMinor, BigInt.from(4280));
    expect(summary.categoryName, 'Food');
    expect(summary.accountName, 'Cash');
    expect(summary.categoryAccountId, accountKeyFood(defaultBookId));
    expect(summary.accountId, accountKeyCash(defaultBookId));
  });

  test('editing a transaction keeps its id and queues an update mutation',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);

    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(3000),
      description: 'Lunch',
    );
    final original = (await repo.watchSummariesSync(defaultBookId)).single;
    final createMutation = (await repo.listPending(defaultBookId)).single;
    await repo.removePending(createMutation.mutationId);

    await service.updateExpense(
      transactionId: original.id,
      occurredAt: original.occurredAt,
      version: original.version,
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(4200),
      description: 'Dinner',
    );

    final updated = (await repo.watchSummariesSync(defaultBookId)).single;
    expect(updated.id, original.id);
    expect(updated.description, 'Dinner');
    expect(updated.amountMinor, BigInt.from(4200));
    expect(await repo.accountBalance(accountKeyFood(defaultBookId)),
        BigInt.from(4200));
    expect(await repo.accountBalance(accountKeyCash(defaultBookId)),
        BigInt.from(-4200));
    final pending = (await repo.listPending(defaultBookId)).single;
    expect(pending.operation, 'update');
    expect(pending.entityId, original.id);
    expect(pending.baseVersion, original.version);
    expect(
      (jsonDecode(pending.payloadJson) as Map)['occurredAt'],
      updated.occurredAt.toUtc().toIso8601String(),
    );
  });

  test('soft delete hides transaction from balance', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);
    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(1000),
      description: 'Taxi',
    );
    final txId = (await repo.watchSummariesSync(defaultBookId)).first.id;
    await service.deleteTransaction(txId);
    expect(
      await repo.accountBalance(accountKeyFood(defaultBookId)),
      BigInt.zero,
    );
    final pending = await repo.listPending(defaultBookId);
    expect(pending.any((p) => p.operation == 'delete'), isTrue);
  });

  test('adopting remote clears a conflict without requeueing local work',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    await repo.addConflict(
      bookId: defaultBookId,
      entityId: 'tx-remote-wins',
      reason: 'LEDGER_VERSION_CONFLICT',
      localPayloadJson: jsonEncode({'description': 'Local edit'}),
      remoteVersion: 3,
    );

    final conflict = (await repo.listConflicts(defaultBookId)).single;
    await repo.resolveConflict(
      conflict.id,
      resolution: ConflictResolution.useRemote,
    );

    expect(await repo.listConflicts(defaultBookId), isEmpty);
    expect(await repo.listPending(defaultBookId), isEmpty);
  });

  test('keeping local requeues an update against the remote version', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    final payload = {
      'description': 'Local edit',
      'entries': [
        {'accountId': accountKeyFood(defaultBookId), 'amountMinor': '2500'},
        {'accountId': accountKeyCash(defaultBookId), 'amountMinor': '-2500'},
      ],
    };
    await repo.addConflict(
      bookId: defaultBookId,
      entityId: 'tx-local-wins',
      reason: 'LEDGER_VERSION_CONFLICT',
      localPayloadJson: jsonEncode(payload),
      remoteVersion: 4,
    );

    final conflict = (await repo.listConflicts(defaultBookId)).single;
    await repo.resolveConflict(
      conflict.id,
      resolution: ConflictResolution.keepLocal,
    );

    expect(await repo.listConflicts(defaultBookId), isEmpty);
    final pending = await repo.listPending(defaultBookId);
    expect(pending, hasLength(1));
    expect(pending.single.entityId, 'tx-local-wins');
    expect(pending.single.operation, 'update');
    expect(pending.single.baseVersion, 4);
    expect(jsonDecode(pending.single.payloadJson), payload);
  });

  test('keeping local requeues a delete conflict as a delete mutation',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    await repo.addConflict(
      bookId: defaultBookId,
      entityId: 'tx-delete-local',
      reason: 'LEDGER_VERSION_CONFLICT',
      localPayloadJson: jsonEncode({'deleted': true}),
      remoteVersion: 5,
    );

    final conflict = (await repo.listConflicts(defaultBookId)).single;
    await repo.resolveConflict(
      conflict.id,
      resolution: ConflictResolution.keepLocal,
    );

    final pending = await repo.listPending(defaultBookId);
    expect(pending, hasLength(1));
    expect(pending.single.operation, 'delete');
    expect(pending.single.baseVersion, 5);
  });

  test('sync refuses to rebind a local ledger to another account', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: () async => 'test-device',
    );
    await repo.seedIfEmpty();
    await repo.updateSyncState(
      bookId: defaultBookId,
      remoteBookId: 'remote-book-one',
      cursor: 42,
    );
    final gateway = FakeAuthGateway()
      ..restoreResult = const AuthSession(
        bookId: 'remote-book-two',
        plan: 'free',
      );
    await gateway.restore();
    final sync = SyncService(repo, SyncApi(dio: Dio()), gateway);

    final result = await sync.syncNow();

    expect(result.ok, isFalse);
    expect(result.message, contains('本地账本已绑定到其他账户'));
    final state = await repo.syncState(defaultBookId);
    expect(state?.remoteBookId, 'remote-book-one');
    expect(state?.cursor, 42);
  });
}
