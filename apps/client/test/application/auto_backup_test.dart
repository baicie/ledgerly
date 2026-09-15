import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/auto_backup.dart';
import 'package:ledgerly_client/application/backup_auto_password_store.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
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
  group('BackupSchedule.isDue', () {
    const enabled = BackupSchedule(enabled: true, intervalDays: 7);
    final now = DateTime.utc(2026, 1, 8);

    test('disabled schedules are never due', () {
      const disabled = BackupSchedule(enabled: false, intervalDays: 1);
      expect(disabled.isDue(null, now), isFalse);
    });

    test('missing last backup is due when enabled', () {
      expect(enabled.isDue(null, now), isTrue);
    });

    test('becomes due on the interval boundary', () {
      expect(
        enabled.isDue(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 8)),
        isTrue,
      );
      expect(
        enabled.isDue(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 7)),
        isFalse,
      );
    });
  });

  group('BackupScheduleStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to disabled / 7 days', () async {
      final store = BackupScheduleStore();
      final schedule = await store.read();
      expect(schedule.enabled, isFalse);
      expect(schedule.intervalDays, kBackupAutoDefaultIntervalDays);
      expect(schedule.encrypted, isFalse);
    });

    test('persists the switch and interval', () async {
      final store = BackupScheduleStore();
      await store.save(
        const BackupSchedule(
          enabled: true,
          intervalDays: 14,
          encrypted: true,
        ),
      );
      final roundTrip = await store.read();
      expect(roundTrip.enabled, isTrue);
      expect(roundTrip.intervalDays, 14);
      expect(roundTrip.encrypted, isTrue);
    });

    test('falls back when a persisted interval is not in the allow-list',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(BackupScheduleStore.kEnabled, true);
      await prefs.setInt(BackupScheduleStore.kIntervalDays, 99);
      final schedule = await BackupScheduleStore().read();
      expect(schedule.enabled, isTrue);
      expect(schedule.intervalDays, kBackupAutoDefaultIntervalDays);
    });

    test('survives a backup-metadata reset after wipe', () async {
      final scheduleStore = BackupScheduleStore();
      final metadataStore = BackupMetadataStore();
      await scheduleStore.save(
        const BackupSchedule(enabled: true, intervalDays: 14),
      );
      await metadataStore.record(
        path: 'memory-backup-1',
        at: DateTime.utc(2026, 1, 1),
      );

      await metadataStore.reset();

      final schedule = await scheduleStore.read();
      expect(schedule.enabled, isTrue);
      expect(schedule.intervalDays, 14);
      expect((await metadataStore.read()).lastBackupAt, isNull);
    });
  });

  group('AutoBackupCoordinator', () {
    late AppDatabase database;
    late InMemoryBackupFilePort filePort;
    late BackupService backups;
    late BackupScheduleStore schedule;
    late BackupMetadataStore metadata;
    late MemoryBackupAutoPasswordStore passwords;
    late AutoBackupCoordinator coordinator;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase.forTesting(NativeDatabase.memory());
      final ledgerRepository = LedgerRepository(
        database,
        deviceIdLoader: () async => 'auto-backup-test-device',
      );
      await ledgerRepository.seedIfEmpty();
      filePort = InMemoryBackupFilePort();
      metadata = BackupMetadataStore();
      passwords = MemoryBackupAutoPasswordStore();
      schedule = BackupScheduleStore();
      backups = BackupService(
        database: database,
        recurring: LocalRecurringRepository(database),
        budgets: LocalBudgetRepository(database),
        attachments: LocalAttachmentRepository(
          database,
          byteStore: MemoryAttachmentByteStore(),
        ),
        merchantRules: MerchantRuleStore(),
        filePort: filePort,
        deviceIdLoader: () async => 'auto-backup-test-device',
        metadata: metadata,
      );
      coordinator = AutoBackupCoordinator(
        schedule: schedule,
        metadata: metadata,
        backups: backups,
        passwords: passwords,
      );
    });

    tearDown(() => database.close());

    test('skips when the switch is off', () async {
      final result = await coordinator.tick();
      expect(result.ran, isFalse);
      expect(result.skipReason, AutoBackupSkipReason.disabled);
      expect(filePort.envelopes, isEmpty);
    });

    test('writes a plaintext snapshot when never backed up', () async {
      await schedule.save(const BackupSchedule(enabled: true));
      final result = await coordinator.tick();
      expect(result.ran, isTrue);
      expect(result.path, isNotNull);
      expect(filePort.envelopes, isNotEmpty);
      expect(filePort.envelopes.values.single.encrypted, isNull);
    });

    test('skips when the last backup is still inside the interval', () async {
      await schedule.save(
        const BackupSchedule(enabled: true, intervalDays: 7),
      );
      await metadata.record(
        path: 'memory-recent',
        at: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      );

      final result = await coordinator.tick();
      expect(result.ran, isFalse);
      expect(result.skipReason, AutoBackupSkipReason.notDue);
      expect(filePort.envelopes, isEmpty);
    });

    test('exports when the last backup is older than the interval', () async {
      await schedule.save(
        const BackupSchedule(enabled: true, intervalDays: 7),
      );
      await metadata.record(
        path: 'memory-stale',
        at: DateTime.now().toUtc().subtract(const Duration(days: 8)),
      );

      final result = await coordinator.tick();
      expect(result.ran, isTrue);
      expect(filePort.envelopes, isNotEmpty);
    });

    test('a successful tick is not immediately due again', () async {
      await schedule.save(const BackupSchedule(enabled: true));
      final first = await coordinator.tick();
      expect(first.ran, isTrue);

      final second = await coordinator.tick();
      expect(second.ran, isFalse);
      expect(second.skipReason, AutoBackupSkipReason.notDue);
      expect(filePort.envelopes.length, 1);
    });

    test('later automatic backups use the local incremental base', () async {
      await schedule.save(
        const BackupSchedule(enabled: true, intervalDays: 1),
      );
      final first = await coordinator.tick();
      expect(first.ran, isTrue);

      final second = await coordinator.tick(
        now: DateTime.now().toUtc().add(const Duration(days: 2)),
      );
      expect(second.ran, isTrue);
      expect(filePort.envelopes.values.last.isIncremental, isTrue);
      expect((await metadata.read()).lastBackupIncremental, isTrue);
    });

    test('encrypted mode skips when no password is stored', () async {
      await schedule.save(
        const BackupSchedule(enabled: true, encrypted: true),
      );

      final result = await coordinator.tick();

      expect(result.ran, isFalse);
      expect(
        result.skipReason,
        AutoBackupSkipReason.encryptedPasswordMissing,
      );
      expect(filePort.envelopes, isEmpty);
    });

    test('encrypted mode writes a standalone encrypted full backup', () async {
      await passwords.write('password123');
      await schedule.save(
        const BackupSchedule(enabled: true, encrypted: true),
      );

      final result = await coordinator.tick();

      expect(result.ran, isTrue);
      expect(filePort.envelopes.values.single.encrypted, isNotNull);
      expect(filePort.envelopes.values.single.isIncremental, isFalse);
      final stored = await metadata.read();
      expect(stored.lastBackupEncrypted, isTrue);
      expect(stored.lastBackupIncremental, isFalse);
      expect(stored.baseBackupId, isNull);
    });

    test('encrypted mode skips when secure storage is unavailable', () async {
      final unavailable = _ThrowingPasswordStore();
      final unavailableCoordinator = AutoBackupCoordinator(
        schedule: schedule,
        metadata: metadata,
        backups: backups,
        passwords: unavailable,
      );
      await schedule.save(
        const BackupSchedule(enabled: true, encrypted: true),
      );

      final result = await unavailableCoordinator.tick();

      expect(result.ran, isFalse);
      expect(
        result.skipReason,
        AutoBackupSkipReason.encryptedPasswordUnavailable,
      );
      expect(filePort.envelopes, isEmpty);
    });

    test('swallows export failures instead of throwing', () async {
      final failing = BackupService(
        database: database,
        recurring: LocalRecurringRepository(database),
        budgets: LocalBudgetRepository(database),
        attachments: LocalAttachmentRepository(
          database,
          byteStore: MemoryAttachmentByteStore(),
        ),
        merchantRules: MerchantRuleStore(),
        filePort: _ThrowingBackupFilePort(),
        deviceIdLoader: () async => 'auto-backup-test-device',
        metadata: metadata,
      );
      final failingCoordinator = AutoBackupCoordinator(
        schedule: schedule,
        metadata: metadata,
        backups: failing,
        passwords: passwords,
      );
      await schedule.save(const BackupSchedule(enabled: true));

      final result = await failingCoordinator.tick();
      expect(result.ran, isFalse);
      expect(result.error, isA<StateError>());
      expect((await metadata.read()).lastBackupAt, isNull);
    });

    test('overlapping ticks skip with inProgress', () async {
      final gate = Completer<void>();
      final gatedPort = _GatedBackupFilePort(gate);
      final gatedBackups = BackupService(
        database: database,
        recurring: LocalRecurringRepository(database),
        budgets: LocalBudgetRepository(database),
        attachments: LocalAttachmentRepository(
          database,
          byteStore: MemoryAttachmentByteStore(),
        ),
        merchantRules: MerchantRuleStore(),
        filePort: gatedPort,
        deviceIdLoader: () async => 'auto-backup-test-device',
        metadata: metadata,
      );
      final gatedCoordinator = AutoBackupCoordinator(
        schedule: schedule,
        metadata: metadata,
        backups: gatedBackups,
        passwords: passwords,
      );
      await schedule.save(const BackupSchedule(enabled: true));

      final first = gatedCoordinator.tick();
      final overlapping = await gatedCoordinator.tick();
      expect(overlapping.skipReason, AutoBackupSkipReason.inProgress);

      gate.complete();
      final finished = await first;
      expect(finished.ran, isTrue);
    });
  });
}

class _ThrowingBackupFilePort extends InMemoryBackupFilePort {
  @override
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  }) {
    throw StateError('disk full');
  }
}

class _GatedBackupFilePort extends InMemoryBackupFilePort {
  _GatedBackupFilePort(this._gate);

  final Completer<void> _gate;

  @override
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    await _gate.future;
    return super.writeBackup(document, deviceId: deviceId);
  }
}

class _ThrowingPasswordStore implements BackupAutoPasswordStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> read() {
    throw StateError('secure storage unavailable');
  }

  @override
  Future<void> write(String password) async {}
}
