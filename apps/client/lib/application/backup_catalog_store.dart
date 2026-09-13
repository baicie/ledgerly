import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackupArtifactKind { full, incremental, encrypted }

enum BackupArtifactSource { manual, automatic, safety }

@immutable
class BackupArtifact {
  const BackupArtifact({
    required this.backupId,
    required this.path,
    required this.createdAt,
    required this.kind,
    required this.source,
    required this.sizeBytes,
    this.sha256,
    this.baseBackupId,
  });

  final String backupId;
  final String path;
  final DateTime createdAt;
  final BackupArtifactKind kind;
  final BackupArtifactSource source;
  final int sizeBytes;
  final String? sha256;
  final String? baseBackupId;

  BackupArtifact copyWith({
    int? sizeBytes,
    String? sha256,
    String? baseBackupId,
  }) {
    return BackupArtifact(
      backupId: backupId,
      path: path,
      createdAt: createdAt,
      kind: kind,
      source: source,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      baseBackupId: baseBackupId ?? this.baseBackupId,
    );
  }

  Map<String, dynamic> toJson() => {
        'backupId': backupId,
        'path': path,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'kind': kind.name,
        'source': source.name,
        'sizeBytes': sizeBytes,
        if (sha256 != null) 'sha256': sha256,
        if (baseBackupId != null) 'baseBackupId': baseBackupId,
      };

  static BackupArtifact? fromJson(Map<String, dynamic> json) {
    final backupId = json['backupId'];
    final path = json['path'];
    final createdAtRaw = json['createdAt'];
    final kindRaw = json['kind'];
    final sourceRaw = json['source'];
    if (backupId is! String ||
        path is! String ||
        createdAtRaw is! String ||
        kindRaw is! String ||
        sourceRaw is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    final kind = BackupArtifactKind.values
        .where((value) => value.name == kindRaw)
        .firstOrNull;
    final source = BackupArtifactSource.values
        .where((value) => value.name == sourceRaw)
        .firstOrNull;
    if (createdAt == null || kind == null || source == null) return null;
    return BackupArtifact(
      backupId: backupId,
      path: path,
      createdAt: createdAt.toUtc(),
      kind: kind,
      source: source,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String?,
      baseBackupId: json['baseBackupId'] as String?,
    );
  }
}

/// SharedPreferences-backed inventory of backup files written by this app.
/// Catalog failures are auxiliary and must never make a successful backup
/// appear failed to the caller.
class BackupCatalogStore {
  BackupCatalogStore({Future<SharedPreferences> Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String preferencesKey = 'ledgerly.backup.catalog';
  static const int targetSize = 100;

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<List<BackupArtifact>> read() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(preferencesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final artifacts = <BackupArtifact>[];
      for (final item in decoded.whereType<Map>()) {
        final artifact = BackupArtifact.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (artifact != null) artifacts.add(artifact);
      }
      artifacts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return artifacts;
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(BackupArtifact artifact) async {
    final artifacts = [...await read()];
    artifacts.removeWhere(
      (item) =>
          item.backupId == artifact.backupId || item.path == artifact.path,
    );
    artifacts.add(artifact);
    artifacts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save(_bounded(artifacts));
  }

  Future<void> removeByPath(String path) async {
    final artifacts = [...await read()];
    artifacts.removeWhere((item) => item.path == path);
    await _save(_bounded(artifacts));
  }

  Future<void> clear() async {
    final prefs = await _prefsLoader();
    await prefs.remove(preferencesKey);
  }

  Future<void> _save(List<BackupArtifact> artifacts) async {
    final prefs = await _prefsLoader();
    await prefs.setString(
      preferencesKey,
      jsonEncode([for (final artifact in artifacts) artifact.toJson()]),
    );
  }

  List<BackupArtifact> _bounded(List<BackupArtifact> artifacts) {
    final manual = [
      for (final artifact in artifacts)
        if (artifact.source == BackupArtifactSource.manual) artifact,
    ];
    final nonManual = [
      for (final artifact in artifacts)
        if (artifact.source != BackupArtifactSource.manual) artifact,
    ];
    final remaining = targetSize - manual.length;
    if (remaining <= 0) return manual;
    return [...manual, ...nonManual.take(remaining)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
