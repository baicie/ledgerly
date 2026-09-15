import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of when the user last successfully exported a backup.
/// Lives in SharedPreferences so the data governance page can render
/// "上次备份: X 天前" even after the app restarts.
class BackupMetadata {
  const BackupMetadata({
    this.lastBackupAt,
    this.lastBackupPath,
    this.lastAttachmentCount = 0,
    this.lastAttachmentSizeBytes = 0,
    this.lastBackupEncrypted = false,
    this.lastBackupId,
    this.lastBackupIncremental = false,
    this.baseBackupId,
    this.baseBackupPath,
  });

  /// UTC instant of the last successful [BackupService.exportToFile].
  final DateTime? lastBackupAt;

  /// File path the last backup was written to. Surfaced in the UI so
  /// the user can jump straight to the file from the data governance
  /// page without digging through the share sheet.
  final String? lastBackupPath;

  /// Number of attachment binaries that were bundled into the last
  /// backup. `0` when the export produced a legacy v1 file that did
  /// not bundle binaries, or when the device has no attachments.
  final int lastAttachmentCount;

  /// Total bytes those attachment binaries consumed. Powers the
  /// "N 个附件 · M MB" hint on the status card.
  final int lastAttachmentSizeBytes;

  /// Phase 10: whether the last backup was sealed with a password.
  /// Surfaced in the status card so the user remembers the file
  /// requires a password to restore.
  final bool lastBackupEncrypted;

  /// Stable ID of the most recent output file.
  final String? lastBackupId;

  /// Whether the most recent output was a delta file.
  final bool lastBackupIncremental;

  /// Local unencrypted full backup used as the delta base.
  final String? baseBackupId;
  final String? baseBackupPath;

  bool get hasBackup => lastBackupAt != null;

  bool get hasIncrementalBase => baseBackupId != null && baseBackupPath != null;

  /// Age since the last backup, or `null` if there isn't one.
  Duration? ageFrom(DateTime now) =>
      lastBackupAt == null ? null : now.difference(lastBackupAt!);

  /// True when no backup exists, **or** when the last backup is older
  /// than the staleness threshold. The threshold is 14 days — anything
  /// older than that earns the "stale banner" on the data governance
  /// page.
  bool get isStale {
    final at = lastBackupAt;
    if (at == null) return true;
    return DateTime.now().difference(at).inDays >= 14;
  }

  /// Same as [isStale] but with an injectable `now`, so widget tests
  /// can fast-forward without monkey-patching `DateTime.now`.
  bool isStaleAt(DateTime now) {
    final at = lastBackupAt;
    if (at == null) return true;
    return now.difference(at).inDays >= 14;
  }

  static const BackupMetadata empty = BackupMetadata();
}

/// Threshold after which a backup is considered "stale" and the
/// reminder banner shows on the data governance page.
const int kBackupStaleDays = 14;

/// Persists `BackupMetadata` to SharedPreferences. Tests pass an
/// in-memory `SharedPreferences` via `setMockInitialValues`.
class BackupMetadataStore {
  BackupMetadataStore({Future<SharedPreferences> Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String kLastBackupAt = 'ledgerly.backup.lastAt';
  static const String kLastBackupPath = 'ledgerly.backup.lastPath';
  static const String kLastAttachmentCount =
      'ledgerly.backup.lastAttachmentCount';
  static const String kLastAttachmentSize =
      'ledgerly.backup.lastAttachmentSizeBytes';
  static const String kLastBackupEncrypted = 'ledgerly.backup.lastEncrypted';
  static const String kLastBackupId = 'ledgerly.backup.lastId';
  static const String kLastBackupIncremental =
      'ledgerly.backup.lastIncremental';
  static const String kBaseBackupId = 'ledgerly.backup.baseId';
  static const String kBaseBackupPath = 'ledgerly.backup.basePath';

  final Future<SharedPreferences> Function() _prefsLoader;

  /// Read the current metadata. Returns [BackupMetadata.empty] when
  /// no record has ever been written or when the persisted values are
  /// unreadable.
  Future<BackupMetadata> read() async {
    final prefs = await _prefsLoader();
    final rawAt = prefs.getString(kLastBackupAt);
    final rawPath = prefs.getString(kLastBackupPath);
    final rawCount = prefs.getInt(kLastAttachmentCount) ?? 0;
    final rawSize = prefs.getInt(kLastAttachmentSize) ?? 0;
    final encrypted = prefs.getBool(kLastBackupEncrypted) ?? false;
    final backupId = prefs.getString(kLastBackupId);
    final incremental = prefs.getBool(kLastBackupIncremental) ?? false;
    final baseId = prefs.getString(kBaseBackupId);
    final basePath = prefs.getString(kBaseBackupPath);
    if (rawAt == null) {
      return BackupMetadata(
        lastBackupPath: rawPath,
        lastAttachmentCount: rawCount,
        lastAttachmentSizeBytes: rawSize,
        lastBackupEncrypted: encrypted,
        lastBackupId: backupId,
        lastBackupIncremental: incremental,
        baseBackupId: baseId,
        baseBackupPath: basePath,
      );
    }
    final parsed = DateTime.tryParse(rawAt);
    if (parsed == null) {
      // Corrupted timestamp — wipe the bad value so the next read
      // returns the empty snapshot.
      await prefs.remove(kLastBackupAt);
      return BackupMetadata.empty;
    }
    return BackupMetadata(
      lastBackupAt: parsed,
      lastBackupPath: rawPath,
      lastAttachmentCount: rawCount,
      lastAttachmentSizeBytes: rawSize,
      lastBackupEncrypted: encrypted,
      lastBackupId: backupId,
      lastBackupIncremental: incremental,
      baseBackupId: baseId,
      baseBackupPath: basePath,
    );
  }

  /// Persist that a backup was just successfully written.
  Future<void> record({
    required String path,
    required DateTime at,
    int attachmentCount = 0,
    int attachmentSizeBytes = 0,
    bool encrypted = false,
    String? backupId,
  }) async {
    final prefs = await _prefsLoader();
    await prefs.setString(kLastBackupAt, at.toUtc().toIso8601String());
    await prefs.setString(kLastBackupPath, path);
    await prefs.setInt(kLastAttachmentCount, attachmentCount);
    await prefs.setInt(kLastAttachmentSize, attachmentSizeBytes);
    await prefs.setBool(kLastBackupEncrypted, encrypted);
    await prefs.setBool(kLastBackupIncremental, false);
    if (backupId == null) {
      await prefs.remove(kLastBackupId);
    } else {
      await prefs.setString(kLastBackupId, backupId);
    }
    if (backupId != null && !encrypted) {
      await prefs.setString(kBaseBackupId, backupId);
      await prefs.setString(kBaseBackupPath, path);
    }
  }

  /// Record a successful incremental write while preserving the base
  /// full-backup reference that the delta was built against.
  Future<void> recordIncremental({
    required String path,
    required DateTime at,
    required String backupId,
    required String baseBackupId,
    required String baseBackupPath,
    int attachmentCount = 0,
    int attachmentSizeBytes = 0,
  }) async {
    final prefs = await _prefsLoader();
    await prefs.setString(kLastBackupAt, at.toUtc().toIso8601String());
    await prefs.setString(kLastBackupPath, path);
    await prefs.setInt(kLastAttachmentCount, attachmentCount);
    await prefs.setInt(kLastAttachmentSize, attachmentSizeBytes);
    await prefs.setBool(kLastBackupEncrypted, false);
    await prefs.setBool(kLastBackupIncremental, true);
    await prefs.setString(kLastBackupId, backupId);
    await prefs.setString(kBaseBackupId, baseBackupId);
    await prefs.setString(kBaseBackupPath, baseBackupPath);
  }

  /// Wipe the persisted record. Called after a destructive
  /// [BackupService.wipeLocalData] so the UI doesn't keep showing a
  /// stale timestamp.
  Future<void> reset() async {
    final prefs = await _prefsLoader();
    await prefs.remove(kLastBackupAt);
    await prefs.remove(kLastBackupPath);
    await prefs.remove(kLastAttachmentCount);
    await prefs.remove(kLastAttachmentSize);
    await prefs.remove(kLastBackupEncrypted);
    await prefs.remove(kLastBackupId);
    await prefs.remove(kLastBackupIncremental);
    await prefs.remove(kBaseBackupId);
    await prefs.remove(kBaseBackupPath);
  }
}
