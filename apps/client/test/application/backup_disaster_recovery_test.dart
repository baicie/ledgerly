import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:ledgerly_client/application/backup_encryption.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/merchant_classifier.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

const _payloadKeys = [
  'books',
  'accounts',
  'transactions',
  'transactionEntries',
  'recurringRules',
  'budgets',
  'attachments',
  'merchantRules',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('fresh-install disaster recovery matrix', () {
    test('restores a plaintext full snapshot into an isolated database',
        () async {
      final source = _RecoveryFixture('full-source');
      final target = _RecoveryFixture('full-target');
      addTearDown(source.close);
      addTearDown(target.close);

      final seeded = await _seedFullDataset(source);
      await target.seed();

      final backup = await source.service.export();
      await target.service.restore(backup);

      await _expectRecovered(target, seeded.expected);
    });

    test('restores a plaintext base plus incremental chain', () async {
      final source = _RecoveryFixture('incremental-source');
      final target = _RecoveryFixture('incremental-target');
      addTearDown(source.close);
      addTearDown(target.close);

      final seeded = await _seedFullDataset(source);
      await source.service.exportToFile();
      await _addExpense(
        source,
        bookId: defaultBookId,
        description: 'incremental recovery',
      );
      await (source.db.update(source.db.books)
            ..where((book) => book.id.equals(defaultBookId)))
          .write(const BooksCompanion(name: Value('Recovered book')));
      await source.budgets.delete(seeded.budgetId);

      final expected = await source.service.export();
      final deltaPath = await source.service.exportToFile(incremental: true);
      source.filePort.pickResult = deltaPath;
      final materialized = await source.service.pickAndRead();
      expect(materialized, isNotNull);
      expect(materialized!.isIncremental, isFalse);

      await target.seed();
      await target.service.restore(materialized);

      await _expectRecovered(target, expected);
    });

    test('restores an encrypted snapshot only with the correct password',
        () async {
      final source = _RecoveryFixture('encrypted-source');
      final target = _RecoveryFixture('encrypted-target');
      addTearDown(source.close);
      addTearDown(target.close);

      final seeded = await _seedFullDataset(source);
      final path = await source.service.exportToFile(
        password: 'password123',
      );
      final locked = await source.filePort.readBackup(path);
      await target.seed();

      await expectLater(
        target.service.restore(locked, password: 'wrong-password'),
        throwsA(isA<BackupPasswordException>()),
      );
      expect(await _count(target.db, 'transactions'), 0);

      await target.service.restore(locked, password: 'password123');
      await _expectRecovered(target, seeded.expected);
    });

    test('imports and restores a snapshot that exists only in the mirror',
        () async {
      final source = _RecoveryFixture('external-source');
      final target = _RecoveryFixture('external-target');
      addTearDown(source.close);
      addTearDown(target.close);

      final seeded = await _seedFullDataset(source);
      final sourcePath = await source.service.exportToFile();
      const externalPath = 'external/ledgerly-backup-recovery.ledgerly.zip';
      target.filePort.rawFiles[externalPath] = Uint8List.fromList(
        source.filePort.rawFiles[sourcePath]!,
      );
      target.filePort.externalExtraFiles.add(externalPath);

      final artifact = await target.service.importExternalBackup(externalPath);
      final imported = await target.filePort.readBackup(artifact.path);
      await target.seed();
      await target.service.restore(imported);

      await _expectRecovered(target, seeded.expected);
    });
  });

  test('replace restore clears stale sync session data from the target',
      () async {
    final source = _RecoveryFixture('session-source');
    final target = _RecoveryFixture('session-target');
    addTearDown(source.close);
    addTearDown(target.close);

    final seeded = await _seedFullDataset(source);
    await target.seed();
    await target.repository.updateSyncState(
      bookId: defaultBookId,
      cursor: 99,
      remoteBookId: 'old-remote-book',
      lastError: 'old sync error',
    );
    await target.repository.addConflict(
      bookId: defaultBookId,
      entityId: 'old-conflict',
      reason: 'stale',
      localPayloadJson: '{}',
    );
    await target.db.into(target.db.pendingMutations).insert(
          PendingMutationsCompanion.insert(
            mutationId: 'old-pending',
            bookId: defaultBookId,
            deviceId: target.deviceId,
            entityType: 'transaction',
            entityId: 'old-transaction',
            operation: 'upsert',
            baseVersion: 0,
            payloadJson: '{}',
            createdAt: DateTime.now().toUtc(),
          ),
        );

    await target.service.restore(await source.service.export());

    await _expectRecovered(target, seeded.expected);
  });
}

Future<void> _expectRecovered(
  _RecoveryFixture target,
  BackupDocument expected,
) async {
  final actual = await target.service.export();
  expect(actual.summary.books, expected.summary.books);
  expect(actual.summary.accounts, expected.summary.accounts);
  expect(actual.summary.transactions, expected.summary.transactions);
  expect(
    actual.summary.transactionEntries,
    expected.summary.transactionEntries,
  );
  expect(actual.summary.recurringRules, expected.summary.recurringRules);
  expect(actual.summary.budgets, expected.summary.budgets);
  expect(actual.summary.attachments, expected.summary.attachments);
  expect(actual.summary.merchantRules, expected.summary.merchantRules);

  for (final key in _payloadKeys) {
    expect(
      _ids(actual.payload[key]),
      _ids(expected.payload[key]),
      reason: '$key IDs',
    );
  }

  final expectedBinary = expected.attachmentBinaries.single;
  final restoredBytes =
      target.byteStore.files['attachments/${expectedBinary.id}'];
  expect(restoredBytes, isNotNull);
  expect(restoredBytes, orderedEquals(expectedBinary.bytes));

  final expectedBookIds = _ids(expected.payload['books']);
  final syncStates = await target.db.select(target.db.syncStates).get();
  expect(syncStates.map((state) => state.bookId).toSet(), expectedBookIds);
  for (final state in syncStates) {
    expect(state.deviceId, target.deviceId);
    expect(state.cursor, 0);
    expect(state.remoteBookId, isNull);
    expect(state.lastError, isNull);
  }
  expect(await _count(target.db, 'pending_mutations'), 0);
  expect(await _count(target.db, 'sync_conflicts'), 0);
}

Set<String> _ids(dynamic raw) {
  if (raw is! List) return const {};
  return raw
      .whereType<Map>()
      .map((row) => row['id'])
      .whereType<String>()
      .toSet();
}

Future<int> _count(AppDatabase db, String table) async {
  final row = await db.customSelect('SELECT COUNT(*) AS count FROM $table',
      readsFrom: {}).getSingle();
  return row.read<int>('count');
}

Future<_RecoverySeed> _seedFullDataset(_RecoveryFixture fixture) async {
  await fixture.seed();
  final archive = await fixture.repository.createBook(name: 'Archive');
  await _addExpense(
    fixture,
    bookId: defaultBookId,
    description: 'primary recovery',
  );
  await _addExpense(
    fixture,
    bookId: archive.id,
    description: 'archive recovery',
  );

  final budget = await fixture.budgets.insert(
    bookId: defaultBookId,
    name: 'Recovery budget',
    amountMinor: BigInt.from(50000),
    categoryAccountId: accountKeyFood(defaultBookId),
  );
  await fixture.recurring.insert(
    bookId: defaultBookId,
    name: 'Recovery rent',
    kind: 'expense',
    amountMinor: BigInt.from(120000),
    categoryAccountId: accountKeyFood(defaultBookId),
    accountId: accountKeyCash(defaultBookId),
    dayOfMonth: 15,
  );

  final attachmentId = const Uuid().v4();
  final attachmentBytes = Uint8List.fromList(
    List<int>.generate(256, (index) => index),
  );
  final relativePath = await fixture.attachments.writeBytes(
    id: attachmentId,
    bytes: attachmentBytes,
  );
  await fixture.attachments.insert(
    id: attachmentId,
    bookId: defaultBookId,
    transactionId: 'recovery-attachment-transaction',
    fileName: 'recovery.bin',
    mime: 'application/octet-stream',
    relativePath: relativePath,
  );
  await fixture.merchantRules.save([
    const MerchantRule(
      id: 'recovery-merchant',
      categoryKey: 'acc_food',
      needles: ['recovery cafe'],
    ),
  ]);
  await fixture.repository.updateSyncState(
    bookId: defaultBookId,
    cursor: 42,
    remoteBookId: 'source-remote-book',
    lastError: 'source sync error',
  );
  await fixture.repository.addConflict(
    bookId: defaultBookId,
    entityId: 'source-conflict',
    reason: 'source conflict',
    localPayloadJson: '{}',
  );

  return _RecoverySeed(
    expected: await fixture.service.export(),
    budgetId: budget.id,
  );
}

Future<void> _addExpense(
  _RecoveryFixture fixture, {
  required String bookId,
  required String description,
}) {
  return LedgerAppService(
    fixture.repository,
    bookId: bookId,
  ).createExpense(
    expenseAccountId: accountKeyFood(bookId),
    fundingAccountId: accountKeyCash(bookId),
    amountMinor: BigInt.from(100),
    description: description,
  );
}

class _RecoveryFixture {
  _RecoveryFixture(this.deviceId)
      : db = AppDatabase.forTesting(NativeDatabase.memory()),
        byteStore = MemoryAttachmentByteStore() {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => deviceId,
    );
    recurring = LocalRecurringRepository(db);
    budgets = LocalBudgetRepository(db);
    attachments = LocalAttachmentRepository(db, byteStore: byteStore);
    merchantRules = MerchantRuleStore(
      preferencesKey: 'ledgerly.test.rules.$deviceId',
    );
    filePort = InMemoryBackupFilePort();
    service = BackupService(
      database: db,
      recurring: recurring,
      budgets: budgets,
      attachments: attachments,
      merchantRules: merchantRules,
      filePort: filePort,
      deviceIdLoader: () async => deviceId,
      encryption: BackupEncryption.testing(),
    );
  }

  final String deviceId;
  final AppDatabase db;
  final MemoryAttachmentByteStore byteStore;
  late final LedgerRepository repository;
  late final LocalRecurringRepository recurring;
  late final LocalBudgetRepository budgets;
  late final LocalAttachmentRepository attachments;
  late final MerchantRuleStore merchantRules;
  late final InMemoryBackupFilePort filePort;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}

class _RecoverySeed {
  const _RecoverySeed({
    required this.expected,
    required this.budgetId,
  });

  final BackupDocument expected;
  final String budgetId;
}
