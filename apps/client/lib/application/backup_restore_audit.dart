import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum BackupRestoreAuditStatus { success, failed }

enum BackupRestoreAuditMode { replace, merge }

@immutable
class BackupRestoreAudit {
  const BackupRestoreAudit({
    required this.id,
    required this.at,
    required this.mode,
    required this.status,
    this.backupId,
    this.safetyPath,
    this.errorSummary,
    this.addedBooks = 0,
    this.replacedBooks = 0,
    this.skippedBooks = 0,
  });

  final String id;
  final DateTime at;
  final BackupRestoreAuditMode mode;
  final BackupRestoreAuditStatus status;
  final String? backupId;
  final String? safetyPath;
  final String? errorSummary;
  final int addedBooks;
  final int replacedBooks;
  final int skippedBooks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'mode': mode.name,
        'status': status.name,
        if (backupId != null) 'backupId': backupId,
        if (safetyPath != null) 'safetyPath': safetyPath,
        if (errorSummary != null) 'errorSummary': errorSummary,
        if (addedBooks > 0) 'addedBooks': addedBooks,
        if (replacedBooks > 0) 'replacedBooks': replacedBooks,
        if (skippedBooks > 0) 'skippedBooks': skippedBooks,
      };

  static BackupRestoreAudit? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final atRaw = json['at'];
    final modeRaw = json['mode'];
    final statusRaw = json['status'];
    if (id is! String || atRaw is! String || modeRaw is! String) {
      return null;
    }
    final at = DateTime.tryParse(atRaw);
    final mode = BackupRestoreAuditMode.values
        .where((value) => value.name == modeRaw)
        .firstOrNull;
    final status = BackupRestoreAuditStatus.values
        .where((value) => value.name == statusRaw)
        .firstOrNull;
    if (at == null || mode == null || status == null) return null;
    return BackupRestoreAudit(
      id: id,
      at: at.toUtc(),
      mode: mode,
      status: status,
      backupId: json['backupId'] as String?,
      safetyPath: json['safetyPath'] as String?,
      errorSummary: json['errorSummary'] as String?,
      addedBooks: (json['addedBooks'] as num?)?.toInt() ?? 0,
      replacedBooks: (json['replacedBooks'] as num?)?.toInt() ?? 0,
      skippedBooks: (json['skippedBooks'] as num?)?.toInt() ?? 0,
    );
  }
}

class BackupRestoreAuditStore {
  BackupRestoreAuditStore({Future<SharedPreferences> Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String preferencesKey = 'ledgerly.backup.restoreAudits';
  static const int targetSize = 50;

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<List<BackupRestoreAudit>> read() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(preferencesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final audits = <BackupRestoreAudit>[];
      for (final item in decoded.whereType<Map>()) {
        final audit = BackupRestoreAudit.fromJson(
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

  Future<void> append(BackupRestoreAudit audit) async {
    final audits = [...await read(), audit]
      ..sort((a, b) => b.at.compareTo(a.at));
    if (audits.length > targetSize) {
      audits.removeRange(targetSize, audits.length);
    }
    final prefs = await _prefsLoader();
    await prefs.setString(
      preferencesKey,
      jsonEncode([for (final item in audits) item.toJson()]),
    );
  }

  Future<void> record({
    required DateTime at,
    required BackupRestoreAuditMode mode,
    required BackupRestoreAuditStatus status,
    String? backupId,
    String? safetyPath,
    String? errorSummary,
    int addedBooks = 0,
    int replacedBooks = 0,
    int skippedBooks = 0,
  }) {
    return append(
      BackupRestoreAudit(
        id: const Uuid().v4(),
        at: at,
        mode: mode,
        status: status,
        backupId: backupId,
        safetyPath: safetyPath,
        errorSummary: errorSummary,
        addedBooks: addedBooks,
        replacedBooks: replacedBooks,
        skippedBooks: skippedBooks,
      ),
    );
  }

  Future<void> remove(String id) async {
    final audits = [...await read()]..removeWhere((audit) => audit.id == id);
    final prefs = await _prefsLoader();
    await prefs.setString(
      preferencesKey,
      jsonEncode([for (final item in audits) item.toJson()]),
    );
  }

  Future<void> clear() async {
    final prefs = await _prefsLoader();
    await prefs.remove(preferencesKey);
  }
}
