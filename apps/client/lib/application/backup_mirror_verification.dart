import 'package:flutter/foundation.dart';

import 'backup_catalog_store.dart';

enum BackupMirrorVerificationStatus {
  healthy,
  missing,
  corrupted,
  extra,
}

@immutable
class BackupMirrorVerificationEntry {
  const BackupMirrorVerificationEntry({
    required this.externalPath,
    required this.status,
    this.artifact,
    this.expectedSha256,
    this.actualSha256,
    this.expectedSizeBytes,
    this.actualSizeBytes,
    this.error,
  });

  final String externalPath;
  final BackupMirrorVerificationStatus status;
  final BackupArtifact? artifact;
  final String? expectedSha256;
  final String? actualSha256;
  final int? expectedSizeBytes;
  final int? actualSizeBytes;
  final String? error;
}

@immutable
class BackupMirrorVerificationReport {
  const BackupMirrorVerificationReport(this.entries);

  final List<BackupMirrorVerificationEntry> entries;

  int get healthyCount => _count(BackupMirrorVerificationStatus.healthy);
  int get missingCount => _count(BackupMirrorVerificationStatus.missing);
  int get corruptedCount => _count(BackupMirrorVerificationStatus.corrupted);
  int get extraCount => _count(BackupMirrorVerificationStatus.extra);

  int _count(BackupMirrorVerificationStatus status) =>
      entries.where((entry) => entry.status == status).length;
}
