import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:ledgerly_client/application/backup_encryption.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('first incremental export falls back to a full base backup', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final path = await fixture.service.exportToFile(incremental: true);
    final document = fixture.filePort.envelopes[path]!;
    final metadata = await BackupMetadataStore().read();

    expect(document.isIncremental, isFalse);
    expect(document.backupId, isNotNull);
    expect(metadata.lastBackupIncremental, isFalse);
    expect(metadata.baseBackupId, document.backupId);
    expect(metadata.baseBackupPath, path);
  });

  test('incremental export contains only changed rows, deletes, and binaries',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final budget = await fixture.budgets.insert(
      bookId: defaultBookId,
      name: 'Baseline budget',
      amountMinor: BigInt.from(10000),
      categoryAccountId: accountKeyFood(defaultBookId),
    );
    final basePath = await fixture.service.exportToFile();
    final base = fixture.filePort.envelopes[basePath]!;

    await fixture.db.update(fixture.db.books).write(
          const BooksCompanion(name: Value('Updated book')),
        );
    await _addExpense(fixture, description: 'new transaction');
    await fixture.budgets.delete(budget.id);
    final attachmentId = const Uuid().v4();
    final bytes = Uint8List.fromList([9, 8, 7, 6]);
    final relativePath = await fixture.attachments.writeBytes(
      id: attachmentId,
      bytes: bytes,
    );
    await fixture.attachments.insert(
      id: attachmentId,
      bookId: defaultBookId,
      transactionId: 'tx-delta',
      fileName: 'delta.bin',
      mime: 'application/octet-stream',
      relativePath: relativePath,
    );

    final deltaPath = await fixture.service.exportToFile(incremental: true);
    final delta = fixture.filePort.envelopes[deltaPath]!;

    expect(delta.isIncremental, isTrue);
    expect(delta.baseBackupId, base.backupId);
    expect(delta.schemaVersion, kIncrementalBackupSchemaVersion);
    expect(delta.summary.books, 1);
    expect(delta.summary.transactions, 1);
    expect(delta.summary.attachments, 1);
    expect((delta.payload['books'] as List), hasLength(1));
    expect((delta.payload['transactions'] as List), hasLength(1));
    expect((delta.payload['accounts'] as List), isEmpty);
    expect(delta.deleted['budgets'], contains(budget.id));
    expect(delta.attachmentBinaries, hasLength(1));
    expect(delta.attachmentBinaries.single.id, attachmentId);
    expect(delta.attachmentBinaries.single.bytes, bytes);
  });

  test('incremental backup is materialized before preview and restore',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();

    await fixture.db.update(fixture.db.books).write(
          const BooksCompanion(name: Value('Materialized book')),
        );
    await _addExpense(fixture, description: 'delta transaction');
    final deltaPath = await fixture.service.exportToFile(incremental: true);
    fixture.filePort.pickResult = deltaPath;

    final picked = await fixture.service.pickAndRead();
    expect(picked, isNotNull);
    expect(picked!.isIncremental, isFalse);
    expect(
        (picked.payload['books'] as List).single['name'], 'Materialized book');
    expect((picked.payload['transactions'] as List), hasLength(1));

    await fixture.service.restore(picked);
    final restored = await fixture.service.export();
    expect(restored.summary.transactions, 1);
    expect((restored.payload['books'] as List).single['name'],
        'Materialized book');
  });

  test('incremental restore fails clearly when the base file is missing',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    final basePath = await fixture.service.exportToFile();
    final deltaPath = await fixture.service.exportToFile(incremental: true);

    fixture.filePort.envelopes.remove(basePath);
    fixture.filePort.rawFiles.remove(basePath);
    fixture.filePort.pickResult = deltaPath;

    await expectLater(
      fixture.service.pickAndRead(),
      throwsA(
        isA<BackupFormatException>().having(
          (error) => error.message,
          'message',
          contains('基础文件'),
        ),
      ),
    );
  });

  test('encrypted export ignores incremental mode and remains self-contained',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final path = await fixture.service.exportToFile(
      password: 'password123',
      incremental: true,
    );
    final document = fixture.filePort.envelopes[path]!;
    final metadata = await BackupMetadataStore().read();

    expect(document.encrypted, isNotNull);
    expect(document.isIncremental, isFalse);
    expect(metadata.lastBackupEncrypted, isTrue);
    expect(metadata.lastBackupIncremental, isFalse);
    expect(metadata.hasIncrementalBase, isFalse);
  });
}

Future<void> _addExpense(
  _Fixture fixture, {
  required String description,
}) {
  return LedgerAppService(fixture.repository).createExpense(
    expenseAccountId: accountKeyFood(defaultBookId),
    fundingAccountId: accountKeyCash(defaultBookId),
    amountMinor: BigInt.from(100),
    description: description,
  );
}

class _Fixture {
  _Fixture()
      : db = AppDatabase.forTesting(NativeDatabase.memory()),
        byteStore = MemoryAttachmentByteStore() {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'incremental-test-device',
    );
    attachments = LocalAttachmentRepository(db, byteStore: byteStore);
    budgets = LocalBudgetRepository(db);
    filePort = InMemoryBackupFilePort();
    service = BackupService(
      database: db,
      recurring: LocalRecurringRepository(db),
      budgets: budgets,
      attachments: attachments,
      merchantRules: MerchantRuleStore(),
      filePort: filePort,
      deviceIdLoader: () async => 'incremental-test-device',
      encryption: BackupEncryption.testing(),
    );
  }

  final AppDatabase db;
  final MemoryAttachmentByteStore byteStore;
  late final LedgerRepository repository;
  late final LocalAttachmentRepository attachments;
  late final LocalBudgetRepository budgets;
  late final InMemoryBackupFilePort filePort;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
