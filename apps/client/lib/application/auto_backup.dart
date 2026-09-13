import 'backup_metadata_store.dart';
import 'backup_schedule.dart';
import 'backup_service.dart';

enum AutoBackupSkipReason { disabled, notDue, inProgress }

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
  })  : _schedule = schedule,
        _metadata = metadata,
        _backups = backups;

  final BackupScheduleStore _schedule;
  final BackupMetadataStore _metadata;
  final BackupService _backups;

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
      final path = await _backups.exportToFile();
      return AutoBackupTickResult.ran(path);
    } catch (error) {
      return AutoBackupTickResult.failed(error);
    } finally {
      _running = false;
    }
  }
}
