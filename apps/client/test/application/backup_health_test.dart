import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_auto_password_store.dart';
import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_health.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_restore_audit.dart';
import 'package:ledgerly_client/application/backup_schedule.dart';
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

  test('reports no backup and automatic backup disabled', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);

    final snapshot = await fixture.health.check();

    expect(snapshot.level, BackupHealthLevel.critical);
    expect(
      snapshot.issues.map((issue) => issue.code),
      containsAll([
        BackupHealthIssueCode.noBackup,
        BackupHealthIssueCode.autoBackupDisabled,
      ]),
    );
    expect(snapshot.recommendedAction, BackupHealthAction.createBackup);
  });

  test('healthy backup policy has no issues', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    await fixture.schedule.save(
      const BackupSchedule(enabled: true, intervalDays: 30),
    );

    final snapshot = await fixture.health.check();

    expect(snapshot.level, BackupHealthLevel.healthy);
    expect(snapshot.issues, isEmpty);
    expect(snapshot.catalogCount, 1);
    expect(snapshot.nextDueAt, isNotNull);
  });

  test('reports stale backup against the configured cadence', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    await fixture.schedule.save(
      const BackupSchedule(enabled: true, intervalDays: 7),
    );
    await fixture.metadata.record(
      path: fixture.filePort.envelopes.keys.single,
      at: DateTime.utc(2026, 1, 1),
    );

    final snapshot = await fixture.health.check(
      now: DateTime.utc(2026, 1, 20),
    );

    expect(snapshot.level, BackupHealthLevel.warning);
    expect(
      snapshot.issues.map((issue) => issue.code),
      contains(BackupHealthIssueCode.staleBackup),
    );
  });

  test('reports encrypted auto backup with missing password', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    await fixture.schedule.save(
      const BackupSchedule(
        enabled: true,
        intervalDays: 30,
        encrypted: true,
      ),
    );

    final snapshot = await fixture.health.check();

    expect(snapshot.level, BackupHealthLevel.critical);
    expect(
      snapshot.issues.map((issue) => issue.code),
      contains(BackupHealthIssueCode.encryptedPasswordMissing),
    );
    expect(
      snapshot.recommendedAction,
      BackupHealthAction.configureAutoPassword,
    );
  });

  test('reports missing catalog files', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    final path = await fixture.service.exportToFile();
    await fixture.filePort.deleteBackup(path);
    await fixture.schedule.save(
      const BackupSchedule(enabled: true, intervalDays: 30),
    );

    final snapshot = await fixture.health.check();

    expect(snapshot.level, BackupHealthLevel.critical);
    expect(
      snapshot.issues.map((issue) => issue.code),
      contains(BackupHealthIssueCode.filesMissing),
    );
    expect(snapshot.recommendedAction, BackupHealthAction.inspectFiles);
  });
}

class _Fixture {
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'health-test-device',
    );
    filePort = InMemoryBackupFilePort();
    metadata = BackupMetadataStore();
    schedule = BackupScheduleStore();
    passwords = MemoryBackupAutoPasswordStore();
    catalog = BackupCatalogStore();
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
      deviceIdLoader: () async => 'health-test-device',
      metadata: metadata,
      catalog: catalog,
      audits: audits,
    );
    health = BackupHealthService(
      metadata: metadata,
      schedule: schedule,
      catalog: catalog,
      passwords: passwords,
      audits: audits,
      backups: service,
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupMetadataStore metadata;
  late final BackupScheduleStore schedule;
  late final MemoryBackupAutoPasswordStore passwords;
  late final BackupCatalogStore catalog;
  late final BackupRestoreAuditStore audits;
  late final BackupService service;
  late final BackupHealthService health;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
