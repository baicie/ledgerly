import 'package:flutter/foundation.dart';

import 'backup_auto_password_store.dart';
import 'backup_catalog_store.dart';
import 'backup_metadata_store.dart';
import 'backup_mirror_store.dart';
import 'backup_restore_audit.dart';
import 'backup_schedule.dart';
import 'backup_service.dart';

enum BackupHealthLevel { healthy, warning, critical }

enum BackupHealthIssueCode {
  noBackup,
  staleBackup,
  autoBackupDisabled,
  encryptedPasswordMissing,
  secureStorageUnavailable,
  verificationFailed,
  filesMissing,
  filesCorrupted,
  latestBackupNotCataloged,
  latestIncremental,
  incrementalBaseMissing,
  recentRestoreFailed,
  externalDirectoryUnavailable,
  latestMirrorFailed,
}

enum BackupHealthAction {
  createBackup,
  enableAutoBackup,
  configureAutoPassword,
  inspectFiles,
  configureExternalDirectory,
  none,
}

@immutable
class BackupHealthIssue {
  const BackupHealthIssue({
    required this.code,
    required this.level,
    this.value,
  });

  final BackupHealthIssueCode code;
  final BackupHealthLevel level;
  final int? value;
}

@immutable
class BackupHealthSnapshot {
  const BackupHealthSnapshot({
    required this.level,
    required this.checkedAt,
    required this.metadata,
    required this.schedule,
    required this.catalogCount,
    required this.issues,
    this.nextDueAt,
  });

  final BackupHealthLevel level;
  final DateTime checkedAt;
  final BackupMetadata metadata;
  final BackupSchedule schedule;
  final int catalogCount;
  final List<BackupHealthIssue> issues;
  final DateTime? nextDueAt;

  bool get hasCritical => level == BackupHealthLevel.critical;
  bool get hasWarnings => issues.any(
        (issue) => issue.level == BackupHealthLevel.warning,
      );

  BackupHealthAction get recommendedAction {
    if (issues.any(
      (issue) =>
          issue.code == BackupHealthIssueCode.noBackup ||
          issue.code == BackupHealthIssueCode.staleBackup,
    )) {
      return BackupHealthAction.createBackup;
    }
    if (issues.any(
      (issue) =>
          issue.code == BackupHealthIssueCode.encryptedPasswordMissing ||
          issue.code == BackupHealthIssueCode.secureStorageUnavailable,
    )) {
      return BackupHealthAction.configureAutoPassword;
    }
    if (issues.any(
      (issue) =>
          issue.code == BackupHealthIssueCode.filesMissing ||
          issue.code == BackupHealthIssueCode.filesCorrupted ||
          issue.code == BackupHealthIssueCode.verificationFailed ||
          issue.code == BackupHealthIssueCode.latestBackupNotCataloged ||
          issue.code == BackupHealthIssueCode.incrementalBaseMissing,
    )) {
      return BackupHealthAction.inspectFiles;
    }
    if (issues.any(
      (issue) =>
          issue.code == BackupHealthIssueCode.externalDirectoryUnavailable ||
          issue.code == BackupHealthIssueCode.latestMirrorFailed,
    )) {
      return BackupHealthAction.configureExternalDirectory;
    }
    if (issues.any(
      (issue) => issue.code == BackupHealthIssueCode.autoBackupDisabled,
    )) {
      return BackupHealthAction.enableAutoBackup;
    }
    return BackupHealthAction.none;
  }
}

class BackupHealthService {
  BackupHealthService({
    required BackupMetadataStore metadata,
    required BackupScheduleStore schedule,
    required BackupCatalogStore catalog,
    required BackupAutoPasswordStore passwords,
    required BackupRestoreAuditStore audits,
    required BackupMirrorStore mirror,
    required BackupFilePort filePort,
    required BackupService backups,
  })  : _metadata = metadata,
        _schedule = schedule,
        _catalog = catalog,
        _passwords = passwords,
        _audits = audits,
        _mirror = mirror,
        _filePort = filePort,
        _backups = backups;

  final BackupMetadataStore _metadata;
  final BackupScheduleStore _schedule;
  final BackupCatalogStore _catalog;
  final BackupAutoPasswordStore _passwords;
  final BackupRestoreAuditStore _audits;
  final BackupMirrorStore _mirror;
  final BackupFilePort _filePort;
  final BackupService _backups;

  Future<BackupHealthSnapshot> check({DateTime? now}) async {
    final checkedAt = (now ?? DateTime.now()).toUtc();
    final metadata = await _metadata.read();
    final schedule = await _schedule.read();
    final catalog = await _catalog.read();
    final audits = await _audits.read();
    final issues = <BackupHealthIssue>[];

    BackupVerificationReport? verification;
    try {
      verification = await _backups.verifyBackups();
    } catch (_) {
      issues.add(
        const BackupHealthIssue(
          code: BackupHealthIssueCode.verificationFailed,
          level: BackupHealthLevel.critical,
        ),
      );
    }

    if (!metadata.hasBackup) {
      issues.add(
        const BackupHealthIssue(
          code: BackupHealthIssueCode.noBackup,
          level: BackupHealthLevel.critical,
        ),
      );
    } else {
      final staleDays =
          schedule.enabled ? schedule.intervalDays : kBackupStaleDays;
      final ageDays = checkedAt.difference(metadata.lastBackupAt!).inDays;
      if (ageDays >= staleDays) {
        issues.add(
          BackupHealthIssue(
            code: BackupHealthIssueCode.staleBackup,
            level: BackupHealthLevel.warning,
            value: ageDays,
          ),
        );
      }
      if (metadata.lastBackupIncremental) {
        issues.add(
          const BackupHealthIssue(
            code: BackupHealthIssueCode.latestIncremental,
            level: BackupHealthLevel.warning,
          ),
        );
      }
      if (metadata.lastBackupPath != null &&
          !catalog.any(
            (artifact) => artifact.path == metadata.lastBackupPath,
          )) {
        issues.add(
          const BackupHealthIssue(
            code: BackupHealthIssueCode.latestBackupNotCataloged,
            level: BackupHealthLevel.warning,
          ),
        );
      }
      if (metadata.hasIncrementalBase &&
          !catalog.any(
            (artifact) => artifact.path == metadata.baseBackupPath,
          )) {
        issues.add(
          const BackupHealthIssue(
            code: BackupHealthIssueCode.incrementalBaseMissing,
            level: BackupHealthLevel.warning,
          ),
        );
      }
    }

    if (!schedule.enabled) {
      issues.add(
        const BackupHealthIssue(
          code: BackupHealthIssueCode.autoBackupDisabled,
          level: BackupHealthLevel.warning,
        ),
      );
    } else if (schedule.encrypted) {
      try {
        final password = await _passwords.read();
        if (password == null || password.length < 8) {
          issues.add(
            const BackupHealthIssue(
              code: BackupHealthIssueCode.encryptedPasswordMissing,
              level: BackupHealthLevel.critical,
            ),
          );
        }
      } catch (_) {
        issues.add(
          const BackupHealthIssue(
            code: BackupHealthIssueCode.secureStorageUnavailable,
            level: BackupHealthLevel.critical,
          ),
        );
      }
    }

    if (verification != null) {
      if (verification.missingCount > 0) {
        issues.add(
          BackupHealthIssue(
            code: BackupHealthIssueCode.filesMissing,
            level: BackupHealthLevel.critical,
            value: verification.missingCount,
          ),
        );
      }
      if (verification.corruptedCount > 0) {
        issues.add(
          BackupHealthIssue(
            code: BackupHealthIssueCode.filesCorrupted,
            level: BackupHealthLevel.critical,
            value: verification.corruptedCount,
          ),
        );
      }
    }

    if (audits.isNotEmpty &&
        audits.first.status == BackupRestoreAuditStatus.failed) {
      issues.add(
        const BackupHealthIssue(
          code: BackupHealthIssueCode.recentRestoreFailed,
          level: BackupHealthLevel.warning,
        ),
      );
    }

    final mirrorDirectory = await _mirror.read();
    if (mirrorDirectory != null) {
      try {
        if (!await _filePort.isBackupDirectoryAvailable(mirrorDirectory)) {
          issues.add(
            const BackupHealthIssue(
              code: BackupHealthIssueCode.externalDirectoryUnavailable,
              level: BackupHealthLevel.warning,
            ),
          );
        }
      } catch (_) {
        issues.add(
          const BackupHealthIssue(
            code: BackupHealthIssueCode.externalDirectoryUnavailable,
            level: BackupHealthLevel.warning,
          ),
        );
      }
      final latestArtifact = catalog
          .where((artifact) => artifact.path == metadata.lastBackupPath)
          .firstOrNull;
      if (latestArtifact?.mirrorStatus == BackupArtifactMirrorStatus.failed) {
        issues.add(
          const BackupHealthIssue(
            code: BackupHealthIssueCode.latestMirrorFailed,
            level: BackupHealthLevel.warning,
          ),
        );
      }
    }

    final level = issues.any(
      (issue) => issue.level == BackupHealthLevel.critical,
    )
        ? BackupHealthLevel.critical
        : issues.any((issue) => issue.level == BackupHealthLevel.warning)
            ? BackupHealthLevel.warning
            : BackupHealthLevel.healthy;
    final nextDueAt = schedule.enabled && metadata.lastBackupAt != null
        ? metadata.lastBackupAt!.add(Duration(days: schedule.intervalDays))
        : null;
    return BackupHealthSnapshot(
      level: level,
      checkedAt: checkedAt,
      metadata: metadata,
      schedule: schedule,
      catalogCount: catalog.length,
      issues: List.unmodifiable(issues),
      nextDueAt: nextDueAt,
    );
  }
}
