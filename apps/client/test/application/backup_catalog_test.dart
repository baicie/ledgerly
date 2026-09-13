import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('catalog upsert replaces the same backup id', () async {
    final store = BackupCatalogStore();
    final createdAt = DateTime.utc(2026, 1, 1);
    await store.upsert(
      BackupArtifact(
        backupId: 'backup-1',
        path: '/old.zip',
        createdAt: createdAt,
        kind: BackupArtifactKind.full,
        source: BackupArtifactSource.manual,
        sizeBytes: 10,
      ),
    );
    await store.upsert(
      BackupArtifact(
        backupId: 'backup-1',
        path: '/new.zip',
        createdAt: createdAt.add(const Duration(minutes: 1)),
        kind: BackupArtifactKind.incremental,
        source: BackupArtifactSource.automatic,
        sizeBytes: 20,
      ),
    );

    final artifacts = await store.read();
    expect(artifacts, hasLength(1));
    expect(artifacts.single.path, '/new.zip');
    expect(artifacts.single.sizeBytes, 20);
  });

  test('cleanup protects manual/base/latest and keeps bounded auto/safety',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    for (var i = 0; i < 5; i++) {
      await fixture.service.exportToFile();
    }
    for (var i = 0; i < 5; i++) {
      await fixture.service.exportToFile(
        incremental: true,
        automatic: true,
      );
    }
    await fixture.service.writeSafetyBackup();
    await fixture.service.writeSafetyBackup();

    final before = await BackupCatalogStore().read();
    expect(before, hasLength(12));
    expect(
      before.where((item) => item.source == BackupArtifactSource.manual),
      hasLength(5),
    );

    final result = await fixture.service.cleanupBackups();
    final after = await BackupCatalogStore().read();
    final metadata = await BackupMetadataStore().read();

    expect(result.deletedCount, 3);
    expect(result.failedCount, 0);
    expect(result.freedBytes, greaterThan(0));
    expect(after, hasLength(9));
    expect(
      after.where((item) => item.source == BackupArtifactSource.manual),
      hasLength(5),
    );
    expect(
      after.where((item) => item.source == BackupArtifactSource.automatic),
      hasLength(3),
    );
    expect(
      after.where((item) => item.source == BackupArtifactSource.safety),
      hasLength(1),
    );
    expect(after.map((item) => item.path), contains(metadata.baseBackupPath));
    expect(after.map((item) => item.path), contains(metadata.lastBackupPath));
    expect(fixture.filePort.rawFiles, hasLength(9));
  });
}

class _Fixture {
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'catalog-test-device',
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
      deviceIdLoader: () async => 'catalog-test-device',
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
