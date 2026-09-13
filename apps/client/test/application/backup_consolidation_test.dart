import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_catalog_store.dart';
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

  test('latest incremental becomes a standalone portable full backup',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final basePath = await fixture.service.exportToFile();
    await fixture.db.update(fixture.db.books).write(
          const BooksCompanion(name: Value('Portable book')),
        );
    await _addExpense(fixture, description: 'portable transaction');
    final deltaPath = await fixture.service.exportToFile(incremental: true);
    final delta = fixture.filePort.envelopes[deltaPath]!;
    expect(delta.isIncremental, isTrue);

    final result = await fixture.service.consolidateLatest();
    expect(result, isNotNull);
    final full = fixture.filePort.envelopes[result!.path]!;
    expect(full.isIncremental, isFalse);
    expect(full.encrypted, isNull);
    expect((full.payload['books'] as List).single['name'], 'Portable book');
    expect(full.summary.transactions, 1);

    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastBackupId, result.backupId);
    expect(metadata.baseBackupId, result.backupId);
    expect(metadata.lastBackupIncremental, isFalse);
    final catalog = await BackupCatalogStore().read();
    final portable = catalog.firstWhere(
      (artifact) => artifact.backupId == result.backupId,
    );
    expect(portable.source, BackupArtifactSource.manual);
    expect(portable.kind, BackupArtifactKind.full);

    // The consolidated file must not depend on either original file.
    await fixture.filePort.deleteBackup(basePath);
    await fixture.filePort.deleteBackup(deltaPath);
    fixture.filePort.pickResult = result.path;
    final picked = await fixture.service.pickAndRead();
    expect(picked, isNotNull);
    expect(picked!.isIncremental, isFalse);
    expect((picked.payload['books'] as List).single['name'], 'Portable book');
  });

  test('encrypted portable backup is standalone and keeps the plaintext base',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final basePath = await fixture.service.exportToFile();
    final base = fixture.filePort.envelopes[basePath]!;
    await fixture.db.update(fixture.db.books).write(
          const BooksCompanion(name: Value('Encrypted portable book')),
        );
    await _addExpense(fixture, description: 'encrypted transaction');
    final deltaPath = await fixture.service.exportToFile(incremental: true);

    final result = await fixture.service.consolidateLatest(
      password: 'password123',
    );
    expect(result, isNotNull);
    final portable = fixture.filePort.envelopes[result!.path]!;
    expect(portable.isIncremental, isFalse);
    expect(portable.isEncrypted, isTrue);
    expect(
      (portable.payload['books'] as List).single['name'],
      'Encrypted portable book',
    );
    expect(portable.summary.transactions, 1);

    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastBackupId, result.backupId);
    expect(metadata.lastBackupEncrypted, isTrue);
    expect(metadata.lastBackupIncremental, isFalse);
    expect(metadata.baseBackupId, base.backupId);
    expect(metadata.baseBackupPath, basePath);

    final catalog = await BackupCatalogStore().read();
    final artifact = catalog.firstWhere(
      (artifact) => artifact.backupId == result.backupId,
    );
    expect(artifact.source, BackupArtifactSource.manual);
    expect(artifact.kind, BackupArtifactKind.encrypted);

    await fixture.filePort.deleteBackup(basePath);
    await fixture.filePort.deleteBackup(deltaPath);
    fixture.filePort.pickResult = result.path;
    await expectLater(
      fixture.service.pickAndRead(password: 'wrong-password'),
      throwsA(isA<BackupPasswordException>()),
    );

    final picked = await fixture.service.pickAndRead(password: 'password123');
    expect(picked, isNotNull);
    expect(picked!.isIncremental, isFalse);
    expect(
      (picked.payload['books'] as List).single['name'],
      'Encrypted portable book',
    );
  });

  test('consolidation is a no-op when latest backup is already full', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();

    expect(await fixture.service.consolidateLatest(), isNull);
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
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'consolidation-test-device',
    );
    filePort = InMemoryBackupFilePort();
    service = BackupService(
      database: db,
      recurring: LocalRecurringRepository(db),
      budgets: LocalBudgetRepository(db),
      attachments: LocalAttachmentRepository(
        db,
        byteStore: MemoryAttachmentByteStore(),
      ),
      merchantRules: MerchantRuleStore(),
      filePort: filePort,
      deviceIdLoader: () async => 'consolidation-test-device',
      encryption: BackupEncryption.testing(),
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
