import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackupRecoveryDrillAuditStatus { success, failed }

@immutable
class BackupRecoveryDrillAudit {
  const BackupRecoveryDrillAudit({
    required this.at,
    required this.status,
    this.encrypted = false,
    this.incremental = false,
    this.bookCount = 0,
    this.transactionCount = 0,
    this.attachmentCount = 0,
  });

  final DateTime at;
  final BackupRecoveryDrillAuditStatus status;
  final bool encrypted;
  final bool incremental;
  final int bookCount;
  final int transactionCount;
  final int attachmentCount;

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'status': status.name,
        'encrypted': encrypted,
        'incremental': incremental,
        'bookCount': bookCount,
        'transactionCount': transactionCount,
        'attachmentCount': attachmentCount,
      };

  static BackupRecoveryDrillAudit? fromJson(Map<String, dynamic> json) {
    final rawAt = json['at'];
    final rawStatus = json['status'];
    if (rawAt is! String || rawStatus is! String) return null;
    final at = DateTime.tryParse(rawAt);
    final status = BackupRecoveryDrillAuditStatus.values
        .where((value) => value.name == rawStatus)
        .firstOrNull;
    if (at == null || status == null) return null;
    return BackupRecoveryDrillAudit(
      at: at.toUtc(),
      status: status,
      encrypted: json['encrypted'] as bool? ?? false,
      incremental: json['incremental'] as bool? ?? false,
      bookCount: (json['bookCount'] as num?)?.toInt() ?? 0,
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      attachmentCount: (json['attachmentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class BackupRecoveryDrillAuditStore {
  BackupRecoveryDrillAuditStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String preferencesKey = 'ledgerly.backup.recoveryDrillAudits';
  static const int targetSize = 20;

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<List<BackupRecoveryDrillAudit>> read() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(preferencesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final audits = <BackupRecoveryDrillAudit>[];
      for (final item in decoded.whereType<Map>()) {
        final audit = BackupRecoveryDrillAudit.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (audit != null) audits.add(audit);
      }
      audits.sort((a, b) => b.at.compareTo(a.at));
      return audits;
    } catch (_) {
      return const [];
    }
  }

  Future<void> append(BackupRecoveryDrillAudit audit) async {
    final audits = [...await read(), audit]
      ..sort((a, b) => b.at.compareTo(a.at));
    if (audits.length > targetSize) {
      audits.removeRange(targetSize, audits.length);
    }
    final prefs = await _prefsLoader();
    await prefs.setString(
      preferencesKey,
      jsonEncode([for (final audit in audits) audit.toJson()]),
    );
  }

  Future<void> recordSuccess({
    required DateTime at,
    required bool encrypted,
    required bool incremental,
    required int bookCount,
    required int transactionCount,
    required int attachmentCount,
  }) {
    return append(
      BackupRecoveryDrillAudit(
        at: at,
        status: BackupRecoveryDrillAuditStatus.success,
        encrypted: encrypted,
        incremental: incremental,
        bookCount: bookCount,
        transactionCount: transactionCount,
        attachmentCount: attachmentCount,
      ),
    );
  }

  Future<void> recordFailure({required DateTime at}) {
    return append(
      BackupRecoveryDrillAudit(
        at: at,
        status: BackupRecoveryDrillAuditStatus.failed,
      ),
    );
  }

  Future<void> clear() async {
    final prefs = await _prefsLoader();
    await prefs.remove(preferencesKey);
  }
}
