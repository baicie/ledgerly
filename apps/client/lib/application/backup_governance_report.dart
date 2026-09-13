import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'backup_catalog_store.dart';
import 'backup_health.dart';
import 'backup_restore_audit.dart';

const int kBackupGovernanceReportSchemaVersion = 1;

enum BackupGovernanceReportFormat { json, csv }

@immutable
class BackupGovernanceReport {
  const BackupGovernanceReport({
    required this.generatedAt,
    required this.health,
    required this.catalog,
    required this.audits,
  });

  final DateTime generatedAt;
  final BackupHealthSnapshot health;
  final List<BackupArtifact> catalog;
  final List<BackupRestoreAudit> audits;

  Map<String, dynamic> toJson() {
    final metadata = health.metadata;
    final schedule = health.schedule;
    return {
      'kind': 'ledgerly-governance-report',
      'schemaVersion': kBackupGovernanceReportSchemaVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'health': {
        'level': health.level.name,
        'catalogCount': health.catalogCount,
        if (health.nextDueAt != null)
          'nextDueAt': health.nextDueAt!.toUtc().toIso8601String(),
        'issues': [
          for (final issue in health.issues)
            {
              'code': issue.code.name,
              'level': issue.level.name,
              if (issue.value != null) 'value': issue.value,
            },
        ],
      },
      'backup': {
        'hasBackup': metadata.hasBackup,
        if (metadata.lastBackupAt != null)
          'lastBackupAt': metadata.lastBackupAt!.toUtc().toIso8601String(),
        'encrypted': metadata.lastBackupEncrypted,
        'incremental': metadata.lastBackupIncremental,
        'attachmentCount': metadata.lastAttachmentCount,
        'attachmentSizeBytes': metadata.lastAttachmentSizeBytes,
        'hasIncrementalBase': metadata.hasIncrementalBase,
      },
      'schedule': {
        'enabled': schedule.enabled,
        'intervalDays': schedule.intervalDays,
        'encrypted': schedule.encrypted,
      },
      'catalog': _catalogSummary(),
      'restoreAudit': _auditSummary(),
    };
  }

  String toJsonString() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String toCsv() {
    final json = toJson();
    final healthJson = json['health'] as Map<String, dynamic>;
    final backupJson = json['backup'] as Map<String, dynamic>;
    final scheduleJson = json['schedule'] as Map<String, dynamic>;
    final catalogJson = json['catalog'] as Map<String, dynamic>;
    final auditJson = json['restoreAudit'] as Map<String, dynamic>;
    final rows = <List<String>>[
      ['metric', 'value'],
      ['schemaVersion', '$kBackupGovernanceReportSchemaVersion'],
      ['generatedAt', json['generatedAt'] as String],
      ['healthLevel', healthJson['level'] as String],
      ['catalogCount', '${healthJson['catalogCount']}'],
      ['issueCount', '${(healthJson['issues'] as List).length}'],
      ['hasBackup', '${backupJson['hasBackup']}'],
      ['lastBackupEncrypted', '${backupJson['encrypted']}'],
      ['lastBackupIncremental', '${backupJson['incremental']}'],
      ['attachmentCount', '${backupJson['attachmentCount']}'],
      ['attachmentSizeBytes', '${backupJson['attachmentSizeBytes']}'],
      ['autoBackupEnabled', '${scheduleJson['enabled']}'],
      ['autoBackupIntervalDays', '${scheduleJson['intervalDays']}'],
      ['autoBackupEncrypted', '${scheduleJson['encrypted']}'],
      ['catalogTotalSizeBytes', '${catalogJson['totalSizeBytes']}'],
      ['catalogFull', '${catalogJson['full']}'],
      ['catalogIncremental', '${catalogJson['incremental']}'],
      ['catalogEncrypted', '${catalogJson['encrypted']}'],
      ['restoreAuditCount', '${auditJson['count']}'],
      ['restoreAuditSuccesses', '${auditJson['successCount']}'],
      ['restoreAuditFailures', '${auditJson['failureCount']}'],
    ];
    return '${rows.map((row) => row.map(_csvCell).join(',')).join('\n')}\n';
  }

  Map<String, dynamic> _catalogSummary() {
    return {
      'count': catalog.length,
      'totalSizeBytes': catalog.fold<int>(
        0,
        (sum, artifact) => sum + artifact.sizeBytes,
      ),
      'full': _countKind(BackupArtifactKind.full),
      'incremental': _countKind(BackupArtifactKind.incremental),
      'encrypted': _countKind(BackupArtifactKind.encrypted),
      'manual': _countSource(BackupArtifactSource.manual),
      'automatic': _countSource(BackupArtifactSource.automatic),
      'safety': _countSource(BackupArtifactSource.safety),
      'withSha256': catalog.where((artifact) => artifact.sha256 != null).length,
    };
  }

  Map<String, dynamic> _auditSummary() {
    final latest = audits.isEmpty ? null : audits.first;
    return {
      'count': audits.length,
      'successCount': audits
          .where((audit) => audit.status == BackupRestoreAuditStatus.success)
          .length,
      'failureCount': audits
          .where((audit) => audit.status == BackupRestoreAuditStatus.failed)
          .length,
      if (latest != null) 'lastAt': latest.at.toUtc().toIso8601String(),
      if (latest != null) 'lastStatus': latest.status.name,
      if (latest != null) 'lastMode': latest.mode.name,
    };
  }

  int _countKind(BackupArtifactKind kind) =>
      catalog.where((artifact) => artifact.kind == kind).length;

  int _countSource(BackupArtifactSource source) =>
      catalog.where((artifact) => artifact.source == source).length;
}

class BackupGovernanceReportService {
  BackupGovernanceReportService({
    required BackupHealthService health,
    required BackupCatalogStore catalog,
    required BackupRestoreAuditStore audits,
  })  : _health = health,
        _catalog = catalog,
        _audits = audits;

  final BackupHealthService _health;
  final BackupCatalogStore _catalog;
  final BackupRestoreAuditStore _audits;

  Future<BackupGovernanceReport> build({DateTime? now}) async {
    final health = await _health.check(now: now);
    final catalog = await _catalog.read();
    final audits = await _audits.read();
    return BackupGovernanceReport(
      generatedAt: health.checkedAt,
      health: health,
      catalog: catalog,
      audits: audits,
    );
  }
}

String _csvCell(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
