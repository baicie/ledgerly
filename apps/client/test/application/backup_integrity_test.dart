import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_encryption.dart';
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

  test('verifies full, incremental, and encrypted backup containers', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    await fixture.service.exportToFile();
    await fixture.service.exportToFile(incremental: true);
    await fixture.service.exportToFile(password: 'password123');

    final report = await fixture.service.verifyBackups();

    expect(report.entries, hasLength(3));
    expect(report.healthyCount, 3);
    expect(report.missingCount, 0);
    expect(report.corruptedCount, 0);
    expect(
      (await BackupCatalogStore().read()).every(
        (artifact) => artifact.sha256 != null,
      ),
      isTrue,
    );
  });

  test('reports missing and corrupted files without deleting them', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final missingPath = await fixture.service.exportToFile();
    final corruptedPath = await fixture.service.exportToFile(
      incremental: true,
    );
    await fixture.filePort.deleteBackup(missingPath);
    fixture.filePort.rawFiles[corruptedPath] = Uint8List.fromList([1, 2, 3]);

    final report = await fixture.service.verifyBackups();

    expect(report.healthyCount, 0);
    expect(report.missingCount, 1);
    expect(report.corruptedCount, 1);
    expect(
      report.entries
          .firstWhere(
            (entry) => entry.artifact.path == missingPath,
          )
          .status,
      BackupVerificationStatus.missing,
    );
    expect(
      report.entries
          .firstWhere(
            (entry) => entry.artifact.path == corruptedPath,
          )
          .status,
      BackupVerificationStatus.corrupted,
    );
    expect(fixture.filePort.rawFiles.containsKey(corruptedPath), isTrue);
  });

  test('legacy catalog entries are backfilled with SHA-256', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    final catalog = BackupCatalogStore();
    final original = (await catalog.read()).single;
    await catalog.upsert(
      BackupArtifact(
        backupId: original.backupId,
        path: original.path,
        createdAt: original.createdAt,
        kind: original.kind,
        source: original.source,
        sizeBytes: original.sizeBytes,
      ),
    );

    final report = await fixture.service.verifyBackups();
    final updated = (await catalog.read()).single;

    expect(report.healthyCount, 1);
    expect(updated.sha256, isNotNull);
    expect(updated.sha256, report.entries.single.actualSha256);
  });
}

class _Fixture {
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'integrity-test-device',
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
      deviceIdLoader: () async => 'integrity-test-device',
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
