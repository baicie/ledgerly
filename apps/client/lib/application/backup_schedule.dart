import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Allowed auto-backup cadences, in whole days. Anything persisted
/// outside this set falls back to [kBackupAutoDefaultIntervalDays].
const List<int> kBackupAutoIntervalDays = [1, 7, 14, 30];

const int kBackupAutoDefaultIntervalDays = 7;

/// User preference for opportunistic backups. Separate from backup
/// metadata so wiping the ledger does not turn the switch off.
@immutable
class BackupSchedule {
  const BackupSchedule({
    this.enabled = false,
    this.intervalDays = kBackupAutoDefaultIntervalDays,
    this.encrypted = false,
  });

  final bool enabled;
  final int intervalDays;
  final bool encrypted;

  static const BackupSchedule disabled = BackupSchedule();

  /// Whether a snapshot should be written at [now]. A missing
  /// [lastBackupAt] counts as due so the first enable produces a
  /// baseline file.
  bool isDue(DateTime? lastBackupAt, DateTime now) {
    if (!enabled) return false;
    if (lastBackupAt == null) return true;
    final age = now.toUtc().difference(lastBackupAt.toUtc());
    return age.inDays >= intervalDays;
  }

  BackupSchedule copyWith({
    bool? enabled,
    int? intervalDays,
    bool? encrypted,
  }) {
    return BackupSchedule(
      enabled: enabled ?? this.enabled,
      intervalDays: intervalDays ?? this.intervalDays,
      encrypted: encrypted ?? this.encrypted,
    );
  }
}

int normalizeBackupAutoIntervalDays(int days) {
  return kBackupAutoIntervalDays.contains(days)
      ? days
      : kBackupAutoDefaultIntervalDays;
}

/// Persists [BackupSchedule] in SharedPreferences.
class BackupScheduleStore {
  BackupScheduleStore({Future<SharedPreferences> Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String kEnabled = 'ledgerly.backup.autoEnabled';
  static const String kIntervalDays = 'ledgerly.backup.autoIntervalDays';
  static const String kEncrypted = 'ledgerly.backup.autoEncrypted';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<BackupSchedule> read() async {
    final prefs = await _prefsLoader();
    final enabled = prefs.getBool(kEnabled) ?? false;
    final rawDays = prefs.getInt(kIntervalDays);
    final encrypted = prefs.getBool(kEncrypted) ?? false;
    return BackupSchedule(
      enabled: enabled,
      intervalDays: normalizeBackupAutoIntervalDays(
        rawDays ?? kBackupAutoDefaultIntervalDays,
      ),
      encrypted: encrypted,
    );
  }

  Future<void> save(BackupSchedule schedule) async {
    final prefs = await _prefsLoader();
    await prefs.setBool(kEnabled, schedule.enabled);
    await prefs.setInt(
      kIntervalDays,
      normalizeBackupAutoIntervalDays(schedule.intervalDays),
    );
    await prefs.setBool(kEncrypted, schedule.encrypted);
  }
}
