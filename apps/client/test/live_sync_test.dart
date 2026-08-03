import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/sync_service.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/auth/session_store.dart';
import 'package:ledgerly_client/config/api_endpoint.dart';
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
    final sessionStore = NativeSessionStore(
      keyValueStore: MemorySessionKeyValueStore(),
      idFactory: () => 'flutter-live-device',
    );
    final auth = AuthRepository(
      endpoint: ApiEndpoint.resolve(
        configured: 'http://127.0.0.1:8080',
        isRelease: false,
        isWeb: false,
      ),
      sessionStore: sessionStore,
    );
    addTearDown(auth.dispose);
    final repo = LedgerRepository(
      db,
      deviceIdLoader: sessionStore.getOrCreateDeviceId,
    );
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);
    final sync = SyncService(
      repo,
      SyncApi(dio: auth.authenticatedClient),
      auth,
    );

    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(888),
      description: 'Live sync',
    );
    expect(await repo.listPending(defaultBookId), hasLength(1));

    try {
      await auth.registerAndLogin(
        email:
            'flutter_e2e_${DateTime.now().microsecondsSinceEpoch}@ledgerly.dev',
        password: 'password123',
        displayName: 'Flutter E2E',
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
