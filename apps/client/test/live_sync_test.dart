import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/sync_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/sync_api.dart';
import 'package:ledgerly_client/domain/ids.dart';

/// Requires local server:
/// DATABASE_URL=postgres://ledgerly:ledgerly@127.0.0.1:5432/ledgerly cargo run --manifest-path ../../server/Cargo.toml -- all
void main() {
  test('client push/pull against live server', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(db);
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);
    final sync = SyncService(repo, SyncApi());

    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(888),
      description: 'Live sync',
    );
    expect(await repo.listPending(defaultBookId), hasLength(1));

    try {
      await sync.ensureSession(
        email: 'flutter_e2e@ledgerly.dev',
        password: 'password123',
      );
    } catch (e) {
      if (Platform.environment['REQUIRE_LIVE_SYNC'] == 'true') {
        fail('live sync server unavailable: $e');
      }
      // ignore: avoid_print
      print('SKIP live sync test: server unavailable ($e)');
      return;
    }

    final result = await sync.syncNow();
    expect(result.ok, isTrue, reason: result.message);
    expect(await repo.listPending(defaultBookId), isEmpty);
    expect(result.cursor, greaterThan(0));
  });
}
