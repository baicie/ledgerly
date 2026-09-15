import 'backup_auto_password_store.dart';
import 'backup_metadata_store.dart';
import 'backup_schedule.dart';
import 'backup_service.dart';

enum AutoBackupSkipReason {
  disabled,
  notDue,
  inProgress,
  encryptedPasswordMissing,
  encryptedPasswordUnavailable,
}

/// Outcome of one opportunistic backup check. [ran] means a new file
/// was written; otherwise [skipReason] or [error] explains why not.
class AutoBackupTickResult {
  const AutoBackupTickResult._({
    required this.ran,
    this.path,
    this.skipReason,
    this.error,
  });

  factory AutoBackupTickResult.ran(String path) =>
      AutoBackupTickResult._(ran: true, path: path);

  factory AutoBackupTickResult.skipped(AutoBackupSkipReason reason) =>
      AutoBackupTickResult._(ran: false, skipReason: reason);

  factory AutoBackupTickResult.failed(Object error) =>
      AutoBackupTickResult._(ran: false, error: error);

  final bool ran;
  final String? path;
  final AutoBackupSkipReason? skipReason;
  final Object? error;
}

/// Foreground scheduler: on app start / resume, write a snapshot when
/// the persisted cadence says we are due. Mirrors
/// [RecurringScheduler.catchUp] — no background isolate, no extra plugin.
class AutoBackupCoordinator {
  AutoBackupCoordinator({
    required BackupScheduleStore schedule,
    required BackupMetadataStore metadata,
    required BackupService backups,
    required BackupAutoPasswordStore passwords,
  })  : _schedule = schedule,
        _metadata = metadata,
        _backups = backups,
        _passwords = passwords;

  final BackupScheduleStore _schedule;
  final BackupMetadataStore _metadata;
  final BackupService _backups;
  final BackupAutoPasswordStore _passwords;

  bool _running = false;

  Future<AutoBackupTickResult> tick({DateTime? now}) async {
    if (_running) {
      return AutoBackupTickResult.skipped(AutoBackupSkipReason.inProgress);
    }
    _running = true;
    try {
      final schedule = await _schedule.read();
      if (!schedule.enabled) {
        return AutoBackupTickResult.skipped(AutoBackupSkipReason.disabled);
      }
      final metadata = await _metadata.read();
      final clock = now ?? DateTime.now().toUtc();
      if (!schedule.isDue(metadata.lastBackupAt, clock)) {
        return AutoBackupTickResult.skipped(AutoBackupSkipReason.notDue);
      }
      String? password;
      if (schedule.encrypted) {
        try {
          password = await _passwords.read();
        } catch (_) {
          return AutoBackupTickResult.skipped(
            AutoBackupSkipReason.encryptedPasswordUnavailable,
          );
        }
        if (password == null || password.length < 8) {
          return AutoBackupTickResult.skipped(
            AutoBackupSkipReason.encryptedPasswordMissing,
          );
        }
      }
      final path = await _backups.exportToFile(
        password: password,
        incremental: !schedule.encrypted,
        automatic: true,
      );
      return AutoBackupTickResult.ran(path);
    } catch (error) {
      return AutoBackupTickResult.failed(error);
    } finally {
      _running = false;
    }
  }
}
