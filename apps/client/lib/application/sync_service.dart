import 'dart:convert';

import '../data/ledger_repository.dart';
import '../data/sync_api.dart';
import '../domain/ids.dart';

class SyncService {
  SyncService(this._repo, this._api);

  final LedgerRepository _repo;
  final SyncApi _api;

  Future<void> ensureSession({
    required String email,
    required String password,
  }) async {
    try {
      await _api.register(
        email: email,
        password: password,
        displayName: 'Local User',
      );
    } catch (_) {}
    final login = await _api.login(
      email: email,
      password: password,
      deviceId: LedgerRepository.deviceId,
    );
    await _repo.updateSyncState(
      bookId: defaultBookId,
      accessToken: login['accessToken'] as String?,
      refreshToken: login['refreshToken'] as String?,
      remoteBookId: login['bookId'] as String?,
      lastError: null,
    );
  }

  String _rewriteAccountId(String id, String fromBook, String toBook) {
    final prefix = '$fromBook:';
    if (id.startsWith(prefix)) {
      return '$toBook:${id.substring(prefix.length)}';
    }
    if (!id.contains(':')) {
      return accountId(toBook, id);
    }
    return id;
  }

  Map<String, dynamic> _rewritePayload(
    Map<String, dynamic> payload,
    String fromBook,
    String toBook,
  ) {
    final entries = (payload['entries'] as List?) ?? const [];
    return {
      ...payload,
      'entries': entries.map((raw) {
        final e = Map<String, dynamic>.from(raw as Map);
        e['accountId'] = _rewriteAccountId(
          e['accountId'] as String,
          fromBook,
          toBook,
        );
        return e;
      }).toList(),
    };
  }

  Future<void> _ensureApiToken(String bookId) async {
    final state = await _repo.syncState(bookId);
    if (state?.accessToken != null) {
      _api.setAccessToken(state!.accessToken);
    }
  }

  Future<SyncRunResult> syncNow({String bookId = defaultBookId}) async {
    try {
      await _ensureApiToken(bookId);
      final state = await _repo.syncState(bookId);
      final remoteBookId = state?.remoteBookId ?? bookId;

      final pending = await _repo.listPending(bookId);
      if (pending.isNotEmpty) {
        final mutations = pending.map((p) {
          final payload = Map<String, dynamic>.from(
            jsonDecode(p.payloadJson) as Map,
          );
          return {
            'mutationId': p.mutationId,
            'entityType': p.entityType,
            'entityId': p.entityId,
            'operation': p.operation,
            'baseVersion': p.baseVersion,
            'schemaVersion': 1,
            'payload': p.operation == 'delete'
                ? payload
                : _rewritePayload(payload, bookId, remoteBookId),
          };
        }).toList();
        final push = await _api.push(
          bookId: remoteBookId,
          deviceId: LedgerRepository.deviceId,
          mutations: mutations,
        );
        final receipts = (push['receipts'] as List).cast<Map>();
        for (final raw in receipts) {
          final receipt = Map<String, dynamic>.from(raw);
          final mutationId = receipt['mutationId'] as String;
          final status = receipt['status'] as String;
          final code = receipt['resultCode'] as String? ?? status;
          final pendingRow =
              pending.firstWhere((p) => p.mutationId == mutationId);
          if (status == 'applied') {
            await _repo.removePending(mutationId);
          } else if (code == 'LEDGER_VERSION_CONFLICT' ||
              code == 'LEDGER_UNBALANCED' ||
              code == 'UNSUPPORTED_MUTATION' ||
              code == 'INVALID_PAYLOAD') {
            await _repo.addConflict(
              bookId: bookId,
              entityId: pendingRow.entityId,
              reason: code,
              localPayloadJson: pendingRow.payloadJson,
              remoteVersion: receipt['entityVersion'] as int?,
            );
            await _repo.removePending(mutationId);
          } else {
            throw StateError('push rejected $mutationId: $status/$code');
          }
        }
      }

      final remainingAfterPush = await _repo.listPending(bookId);
      if (remainingAfterPush.isNotEmpty) {
        throw StateError(
          'push incomplete: ${remainingAfterPush.length} pending remain',
        );
      }

      final cursor = state?.cursor ?? 0;
      final pull = await _api.pull(bookId: remoteBookId, cursor: cursor);
      final changes = (pull['changes'] as List?) ?? const [];
      for (final raw in changes) {
        final change = Map<String, dynamic>.from(raw as Map);
        if (change['entityType'] != 'transaction') continue;
        if (change['operation'] == 'upsert') {
          final payload = _rewritePayload(
            Map<String, dynamic>.from(change['payload'] as Map),
            remoteBookId,
            bookId,
          );
          await _repo.applyRemoteUpsert(
            entityId: change['entityId'] as String,
            bookId: bookId,
            version: change['version'] as int,
            payload: payload,
          );
        } else if (change['operation'] == 'delete') {
          await _repo.applyRemoteDelete(
            entityId: change['entityId'] as String,
            version: change['version'] as int,
          );
        }
      }
      final nextCursor =
          int.tryParse(pull['nextCursor']?.toString() ?? '') ?? cursor;
      await _repo.updateSyncState(
        bookId: bookId,
        cursor: nextCursor,
        lastError: null,
      );
      final remaining = await _repo.listPending(bookId);
      return SyncRunResult(
        ok: true,
        message: 'synced',
        cursor: nextCursor,
        pendingCount: remaining.length,
      );
    } catch (e) {
      await _repo.updateSyncState(bookId: bookId, lastError: e.toString());
      final state = await _repo.syncState(bookId);
      final pending = await _repo.listPending(bookId);
      return SyncRunResult(
        ok: false,
        message: e.toString(),
        cursor: state?.cursor ?? 0,
        pendingCount: pending.length,
      );
    }
  }
}

class SyncRunResult {
  SyncRunResult({
    required this.ok,
    required this.message,
    required this.cursor,
    required this.pendingCount,
  });

  final bool ok;
  final String message;
  final int cursor;
  final int pendingCount;
}
