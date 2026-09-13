import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_auto_password_store.dart';
import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_governance_report.dart';
import 'package:ledgerly_client/application/backup_health.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_mirror_store.dart';
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

  test('JSON and CSV reports expose summaries without sensitive paths',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    await fixture.schedule.save(
      const BackupSchedule(enabled: true, intervalDays: 30),
    );
    await fixture.audits.record(
      at: DateTime.utc(2026, 1, 2),
      mode: BackupRestoreAuditMode.merge,
      status: BackupRestoreAuditStatus.failed,
      backupId: 'backup-secret-id',
      safetyPath: '/secret/path/pre-restore.zip',
      errorSummary: 'sensitive error summary',
    );

    final report = await fixture.reportService.build(
      now: DateTime.utc(2026, 1, 3),
    );
    final json = report.toJsonString();
    final csv = report.toCsv();

    expect(json, contains('"kind": "ledgerly-governance-report"'));
    expect(json, contains('"schemaVersion": 1'));
    expect(json, contains('"catalogCount": 1'));
    expect(json, contains('"lastStatus": "failed"'));
    expect(json, isNot(contains('/secret/path')));
    expect(json, isNot(contains('backup-secret-id')));
    expect(json, isNot(contains('sensitive error summary')));
    expect(csv, contains('healthLevel,warning'));
    expect(csv, contains('restoreAuditFailures,1'));
    expect(csv, isNot(contains('/secret/path')));
    expect(csv, isNot(contains('sensitive error summary')));
  });
}

class _Fixture {
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'report-test-device',
    );
    filePort = InMemoryBackupFilePort();
    metadata = BackupMetadataStore();
    schedule = BackupScheduleStore();
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
      deviceIdLoader: () async => 'report-test-device',
      metadata: metadata,
      catalog: catalog,
      audits: audits,
    );
    health = BackupHealthService(
      metadata: metadata,
      schedule: schedule,
      catalog: catalog,
      passwords: MemoryBackupAutoPasswordStore(),
      audits: audits,
      mirror: BackupMirrorStore(),
      filePort: filePort,
      backups: service,
    );
    reportService = BackupGovernanceReportService(
      health: health,
      catalog: catalog,
      audits: audits,
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupMetadataStore metadata;
  late final BackupScheduleStore schedule;
  late final BackupCatalogStore catalog;
  late final BackupRestoreAuditStore audits;
  late final BackupService service;
  late final BackupHealthService health;
  late final BackupGovernanceReportService reportService;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
