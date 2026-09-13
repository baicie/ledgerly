import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_auto_password_store.dart';
import 'package:ledgerly_client/application/backup_catalog_store.dart';
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

  test('new backup is mirrored when an external directory is configured',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.mirror.save('/external');

    final path = await fixture.service.exportToFile();

    final artifact = (await fixture.catalog.read()).single;
    expect(artifact.mirrorStatus, BackupArtifactMirrorStatus.mirrored);
    expect(artifact.mirrorPath, isNotNull);
    expect(fixture.filePort.mirroredFiles[path], isNotNull);
  });

  test('mirror failure keeps local backup and records failure', () async {
    final fixture = _Fixture(
      filePort: _FailingMirrorPort(),
    );
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.mirror.save('/external');

    final path = await fixture.service.exportToFile();

    final artifact = (await fixture.catalog.read()).single;
    expect(artifact.mirrorStatus, BackupArtifactMirrorStatus.failed);
    expect(artifact.mirrorPath, isNull);
    expect(fixture.filePort.rawFiles.containsKey(path), isTrue);
    expect((await fixture.metadata.read()).lastBackupPath, path);
  });

  test('configured directory mirrors existing catalog artifacts', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    final path = await fixture.service.exportToFile();
    expect((await fixture.catalog.read()).single.mirrorStatus, isNull);

    await fixture.mirror.save('/external');
    final result = await fixture.service.mirrorAllBackups();

    expect(result.mirroredCount, 1);
    expect(result.failedCount, 0);
    expect(fixture.filePort.mirroredFiles[path], isNotNull);
    expect(
      (await fixture.catalog.read()).single.mirrorStatus,
      BackupArtifactMirrorStatus.mirrored,
    );
  });

  test('health reports an unavailable external directory', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    await fixture.mirror.save('/missing');
    fixture.filePort.unavailableDirectories.add('/missing');
    final health = BackupHealthService(
      metadata: fixture.metadata,
      schedule: fixture.schedule,
      catalog: fixture.catalog,
      passwords: MemoryBackupAutoPasswordStore(),
      audits: fixture.audits,
      mirror: fixture.mirror,
      filePort: fixture.filePort,
      backups: fixture.service,
    );

    final snapshot = await health.check();

    expect(snapshot.level, BackupHealthLevel.warning);
    expect(
      snapshot.issues.map((issue) => issue.code),
      contains(BackupHealthIssueCode.externalDirectoryUnavailable),
    );
  });

  test('external mirror verification reports healthy and corrupted copies',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.mirror.save('/external');
    await fixture.service.exportToFile();

    final healthy = await fixture.service.verifyExternalMirror();
    expect(healthy, isNotNull);
    expect(healthy!.healthyCount, 1);
    expect(healthy.corruptedCount, 0);

    final externalPath = fixture.filePort.mirroredFiles.values.single;
    fixture.filePort.rawFiles[externalPath] = Uint8List.fromList([1, 2, 3]);
    final corrupted = await fixture.service.verifyExternalMirror();
    expect(corrupted!.corruptedCount, 1);
  });

  test('external mirror verification reports missing and extra files',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.mirror.save('/external');
    await fixture.service.exportToFile();
    final externalPath = fixture.filePort.mirroredFiles.values.single;
    await fixture.filePort.deleteBackup(externalPath);
    fixture.filePort.externalExtraFiles.add(
      '/external/ledgerly-extra.ledgerly.zip',
    );
    fixture.filePort.rawFiles['/external/ledgerly-extra.ledgerly.zip'] =
        Uint8List.fromList([9, 9, 9]);

    final report = await fixture.service.verifyExternalMirror();

    expect(report!.missingCount, 1);
    expect(report.extraCount, 1);
  });

  test('external extra backup can be imported into the local catalog',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();
    final document = await fixture.service.export();
    final stagingPath = await fixture.filePort.writeBackup(
      document,
      deviceId: 'mirror-test-device',
    );
    final externalPath = '/external/ledgerly-extra.ledgerly.zip';
    fixture.filePort.rawFiles[externalPath] =
        Uint8List.fromList(fixture.filePort.rawFiles[stagingPath]!);
    fixture.filePort.externalExtraFiles.add(externalPath);

    final artifact = await fixture.service.importExternalBackup(externalPath);

    expect(artifact.path, startsWith('memory-imported-'));
    expect(artifact.mirrorPath, externalPath);
    expect(artifact.mirrorStatus, BackupArtifactMirrorStatus.mirrored);
    expect(await fixture.catalog.read(), hasLength(2));
    expect(fixture.filePort.rawFiles.containsKey(artifact.path), isTrue);
  });
}

class _Fixture {
  _Fixture({InMemoryBackupFilePort? filePort})
      : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'mirror-test-device',
    );
    this.filePort = filePort ?? InMemoryBackupFilePort();
    metadata = BackupMetadataStore();
    mirror = BackupMirrorStore();
    catalog = BackupCatalogStore();
    audits = BackupRestoreAuditStore();
    schedule = BackupScheduleStore();
    service = BackupService(
      database: db,
      recurring: LocalRecurringRepository(db),
      budgets: LocalBudgetRepository(db),
      attachments: LocalAttachmentRepository(
        db,
        byteStore: MemoryAttachmentByteStore(),
      ),
      merchantRules: MerchantRuleStore(),
      filePort: this.filePort,
      deviceIdLoader: () async => 'mirror-test-device',
      metadata: metadata,
      mirror: mirror,
      catalog: catalog,
      audits: audits,
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupMetadataStore metadata;
  late final BackupMirrorStore mirror;
  late final BackupCatalogStore catalog;
  late final BackupRestoreAuditStore audits;
  late final BackupScheduleStore schedule;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}

class _FailingMirrorPort extends InMemoryBackupFilePort {
  @override
  Future<String> mirrorBackup(String source, String directory) {
    throw StateError('external directory unavailable');
  }
}
