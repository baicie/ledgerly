import 'dart:convert';

import '../data/ledger_repository.dart';
import '../data/sync_api.dart';

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
    } catch (_) {
      // already registered is fine
    }
    final login = await _api.login(
      email: email,
      password: password,
      deviceId: LedgerRepository.deviceId,
    );
    await _repo.updateSyncState(
      bookId: 'book_default',
      accessToken: login['accessToken'] as String?,
      refreshToken: login['refreshToken'] as String?,
      lastError: null,
    );
  }

  Future<SyncRunResult> syncNow({String bookId = 'book_default'}) async {
    try {
      final pending = await _repo.listPending(bookId);
      if (pending.isNotEmpty) {
        final mutations = pending
            .map(
              (p) => {
                'mutationId': p.mutationId,
                'entityType': p.entityType,
                'entityId': p.entityId,
                'operation': p.operation,
                'baseVersion': p.baseVersion,
                'schemaVersion': 1,
                'payload': jsonDecode(p.payloadJson),
              },
            )
            .toList();
        final push = await _api.push(
          bookId: bookId,
          deviceId: LedgerRepository.deviceId,
          mutations: mutations,
        );
        final receipts = (push['receipts'] as List).cast<Map>();
        for (final raw in receipts) {
          final receipt = Map<String, dynamic>.from(raw);
          final mutationId = receipt['mutationId'] as String;
          final status = receipt['status'] as String;
          final code = receipt['resultCode'] as String;
          final pendingRow =
              pending.firstWhere((p) => p.mutationId == mutationId);
          if (status == 'applied') {
            await _repo.removePending(mutationId);
          } else if (code == 'LEDGER_VERSION_CONFLICT') {
            await _repo.addConflict(
              bookId: bookId,
              entityId: pendingRow.entityId,
              reason: code,
              localPayloadJson: pendingRow.payloadJson,
              remoteVersion: receipt['entityVersion'] as int?,
            );
            await _repo.removePending(mutationId);
          } else if (code == 'LEDGER_UNBALANCED' ||
              code == 'UNSUPPORTED_MUTATION' ||
              code == 'INVALID_PAYLOAD') {
            await _repo.addConflict(
              bookId: bookId,
              entityId: pendingRow.entityId,
              reason: code,
              localPayloadJson: pendingRow.payloadJson,
            );
            await _repo.removePending(mutationId);
          }
        }
      }

      final state = await _repo.syncState(bookId);
      final cursor = state?.cursor ?? 0;
      final pull = await _api.pull(bookId: bookId, cursor: cursor);
      final changes = (pull['changes'] as List?) ?? const [];
      for (final raw in changes) {
        final change = Map<String, dynamic>.from(raw as Map);
        if (change['entityType'] == 'transaction' &&
            change['operation'] == 'upsert') {
          await _repo.applyRemoteUpsert(
            entityId: change['entityId'] as String,
            bookId: bookId,
            version: change['version'] as int,
            payload: Map<String, dynamic>.from(change['payload'] as Map),
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
