// A test harness that boots two Ledgerly "devices" side-by-side,
// each with its own in-memory Drift database, and wires both through
// the same in-process [FakeSyncServer]. Each device carries its own
// SyncService, FakeAuthGateway, and FakeSyncApi so the scenarios in
// `multi_device_sync_test.dart` can exercise push / pull round trips
// without a real network, server, or shared database.
//
// All wiring is explicit — no production Riverpod providers are
// referenced. That keeps the harness hermetic across host VM, Chrome,
// and mobile runners.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/sync_service.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';

import 'fake_auth_gateway.dart';
import 'fake_sync_api.dart';
import 'fake_sync_server.dart';

// Suppress drift's "multiple databases sharing a QueryExecutor" warning:
// each device here owns its own `NativeDatabase.memory()`, so there is no
// shared executor and the warning is a false positive. See
// https://drift.simonbinder.eu/faq/#using-the-database
bool _suppressed = false;
void _suppressDriftWarning() {
  if (_suppressed) return;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  _suppressed = true;
}

/// A single Ledgerly device under test.
class Device {
  Device._({
    required this.label,
    required this.db,
    required this.repository,
    required this.appService,
    required this.syncService,
    required this.fakeApi,
    required this.fakeAuth,
    required this.localBookId,
    required this.remoteBookId,
    required this.deviceId,
  });

  /// Friendly label used in failure messages: "A" or "B".
  final String label;

  /// Per-device in-memory SQLite database.
  final AppDatabase db;

  /// LedgerRepository bound to this device's database.
  final LedgerRepository repository;

  /// LedgerAppService — the entry point for `createExpense` etc.
  final LedgerAppService appService;

  /// SyncService — drives push + pull.
  final SyncService syncService;

  /// The fake SyncApi bound to the shared server.
  final FakeSyncApi fakeApi;

  /// The fake AuthGateway that returns the device's session.
  final FakeAuthGateway fakeAuth;

  /// The local book id (always `book_default` in tests).
  final String localBookId;

  /// The remote book id (always equal to `FakeSyncServer.bookId`).
  final String remoteBookId;

  /// A stable device id used by the server for idempotency.
  final String deviceId;

  Future<void> close() async {
    await db.close();
  }
}

/// Boot two devices that share a single in-process [FakeSyncServer].
class TwoDeviceHarness {
  TwoDeviceHarness._({
    required this.server,
    required this.deviceA,
    required this.deviceB,
  });

  final FakeSyncServer server;
  final Device deviceA;
  final Device deviceB;

  static Future<TwoDeviceHarness> boot({
    String? remoteBookId,
  }) async {
    _suppressDriftWarning();
    final server = FakeSyncServer(bookId: remoteBookId ?? FakeSyncServer.defaultServerBookId);
    final deviceA = await _bootDevice(
      label: 'A',
      server: server,
      deviceId: 'dev_A',
      remoteBookId: server.bookId,
    );
    final deviceB = await _bootDevice(
      label: 'B',
      server: server,
      deviceId: 'dev_B',
      remoteBookId: server.bookId,
    );
    return TwoDeviceHarness._(
      server: server,
      deviceA: deviceA,
      deviceB: deviceB,
    );
  }

  Future<void> close() async {
    await deviceA.close();
    await deviceB.close();
  }

  static Future<Device> _bootDevice({
    required String label,
    required FakeSyncServer server,
    required String deviceId,
    required String remoteBookId,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LedgerRepository(
      db,
      deviceIdLoader: () async => deviceId,
    );
    await repository.seedIfEmpty();

    final appService = LedgerAppService(
      repository,
      bookId: defaultBookId,
    );
    final fakeApi = FakeSyncApi(
      server: server,
      deviceId: deviceId,
    );
    final fakeAuth = FakeAuthGateway(
      session: AuthSession(bookId: remoteBookId, plan: 'free'),
    );
    // Pre-populate `currentSession` so SyncService doesn't have to
    // round-trip through restore() (which would be a no-op anyway in
    // tests but adds an unnecessary microtask).
    await fakeAuth.restore();
    final syncService = SyncService(
      repository,
      fakeApi,
      fakeAuth,
    );

    return Device._(
      label: label,
      db: db,
      repository: repository,
      appService: appService,
      syncService: syncService,
      fakeApi: fakeApi,
      fakeAuth: fakeAuth,
      localBookId: defaultBookId,
      remoteBookId: remoteBookId,
      deviceId: deviceId,
    );
  }
}
