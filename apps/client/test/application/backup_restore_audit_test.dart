import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_restore_audit.dart';
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

  test('restore audit store round-trips and bounds history', () async {
    final store = BackupRestoreAuditStore();
    for (var i = 0; i < BackupRestoreAuditStore.targetSize + 5; i++) {
      await store.record(
        at: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        mode: BackupRestoreAuditMode.replace,
        status: BackupRestoreAuditStatus.success,
        backupId: 'backup-$i',
      );
    }

    final audits = await store.read();

    expect(audits, hasLength(BackupRestoreAuditStore.targetSize));
    expect(audits.first.backupId, 'backup-54');
    expect(audits.last.backupId, 'backup-5');
  });

  test('cleanup protects audited safety backup until history is deleted',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    final auditedPath = await fixture.service.writeSafetyBackup();
    await fixture.audits.record(
      at: DateTime.utc(2026, 1, 1),
      mode: BackupRestoreAuditMode.replace,
      status: BackupRestoreAuditStatus.success,
      safetyPath: auditedPath,
    );
    final newerPath = await fixture.service.writeSafetyBackup();

    await fixture.service.cleanupBackups();

    expect(fixture.filePort.rawFiles.containsKey(auditedPath), isTrue);
    expect(fixture.filePort.rawFiles.containsKey(newerPath), isTrue);

    final audit = (await fixture.audits.read()).single;
    final freed = await fixture.service.deleteRestoreAudit(audit);
    expect(freed, greaterThan(0));
    expect(fixture.filePort.rawFiles.containsKey(auditedPath), isFalse);
    expect(await fixture.audits.read(), isEmpty);
    expect(
      (await BackupCatalogStore().read()).map((artifact) => artifact.path),
      isNot(contains(auditedPath)),
    );
  });
}

class _Fixture {
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'audit-test-device',
    );
    filePort = InMemoryBackupFilePort();
    audits = BackupRestoreAuditStore();
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
      deviceIdLoader: () async => 'audit-test-device',
      metadata: BackupMetadataStore(),
      audits: audits,
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupRestoreAuditStore audits;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
