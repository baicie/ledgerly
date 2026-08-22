import 'dart:convert';

import '../auth/auth_repository.dart';
import '../data/ledger_repository.dart';
import '../data/sync_api.dart';
import '../domain/ids.dart';
import '../l10n/l10n.dart';

class SyncService {
  SyncService(this._repo, this._api, this._auth);

  final LedgerRepository _repo;
  final SyncApi _api;
  final AuthGateway _auth;

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

  Map<String, dynamic> _rewriteTransactionPayload(
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

  Map<String, dynamic> _rewriteAccountPayload(
    Map<String, dynamic> payload,
    String fromBook,
    String toBook,
  ) {
    if (!payload.containsKey('parentAccountId')) return payload;
    final parentAccountId = payload['parentAccountId'];
    if (parentAccountId != null && parentAccountId is! String) {
      throw const FormatException(
        'account parentAccountId must be a string or null',
      );
    }
    final rewrittenParent = parentAccountId == null
        ? null
        : _rewriteAccountId(parentAccountId, fromBook, toBook);
    return {
      ...payload,
      'parentAccountId': rewrittenParent,
    };
  }

  Future<SyncRunResult> syncNow({String bookId = defaultBookId}) async {
    try {
      final session = _auth.currentSession;
      if (session == null) {
        throw StateError('Authentication required');
      }
      final state = await _repo.syncState(bookId);
      final remoteBookId = session.bookId;
      final deviceId = await _repo.deviceId;
      var cursor = state?.cursor ?? 0;
      if (state?.remoteBookId == null) {
        await _repo.updateSyncState(
          bookId: bookId,
          remoteBookId: remoteBookId,
          cursor: 0,
          lastError: null,
        );
        cursor = 0;
      } else if (state!.remoteBookId != remoteBookId) {
        throw StateError(L10n.current.bookBoundToOtherAccount);
      }

      for (var pushAttempt = 0; pushAttempt < 2; pushAttempt++) {
        final pending = await _repo.listPending(bookId);
        if (pending.isEmpty) break;
        final mutations = pending.map((p) {
          final payload = Map<String, dynamic>.from(
            jsonDecode(p.payloadJson) as Map,
          );
          return {
            'mutationId': p.mutationId,
            'entityType': p.entityType,
            'entityId': p.entityType == 'account'
                ? _rewriteAccountId(p.entityId, bookId, remoteBookId)
                : p.entityId,
            'operation': p.operation,
            'baseVersion': p.baseVersion,
            'schemaVersion': 1,
            'payload': p.entityType == 'account'
                ? _rewriteAccountPayload(payload, bookId, remoteBookId)
                : p.operation == 'delete'
                    ? payload
                    : _rewriteTransactionPayload(payload, bookId, remoteBookId),
          };
        }).toList();
        final push = await _api.push(
          bookId: remoteBookId,
          deviceId: deviceId,
          mutations: mutations,
        );
        final receipts = (push['receipts'] as List).cast<Map>();
        final rejectedCategoryEntityIds = <String>{};
        for (final raw in receipts) {
          final receipt = Map<String, dynamic>.from(raw);
          if (receipt['resultCode'] != 'INVALID_CATEGORY_PARENT') continue;
          final mutationId = receipt['mutationId'] as String?;
          for (final row in pending) {
            if (row.mutationId == mutationId && row.entityType == 'account') {
              rejectedCategoryEntityIds.add(row.entityId);
              break;
            }
          }
        }
        for (final raw in receipts) {
          final receipt = Map<String, dynamic>.from(raw);
          final mutationId = receipt['mutationId'] as String;
          final status = receipt['status'] as String;
          final code = receipt['resultCode'] as String? ?? status;
          final pendingRow =
              pending.firstWhere((p) => p.mutationId == mutationId);
          if (status == 'applied') {
            await _repo.removePending(mutationId);
          } else if (code == 'INVALID_CATEGORY_PARENT' &&
              pendingRow.entityType == 'account') {
            await _repo.retryCategoryMutationAsRoot(mutationId);
          } else if (code == 'ACCOUNT_NOT_FOUND' &&
              pendingRow.entityType == 'account' &&
              rejectedCategoryEntityIds.contains(pendingRow.entityId)) {
            await _repo.retryCategoryMutationAsRoot(mutationId);
          } else if (code == 'ACCOUNT_NOT_FOUND' &&
              rejectedCategoryEntityIds.isNotEmpty &&
              pendingRow.entityType == 'transaction') {
            await _repo.renewPendingMutation(mutationId);
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
        final remainingAfterPush = await _repo.listPending(bookId);
        if (remainingAfterPush.isEmpty) break;
        if (pushAttempt == 1) {
          throw StateError(
            'push incomplete: ${remainingAfterPush.length} pending remain',
          );
        }
      }

      final pull = await _api.pull(bookId: remoteBookId, cursor: cursor);
      final changes = (pull['changes'] as List?) ?? const [];
      for (final raw in changes) {
        final change = Map<String, dynamic>.from(raw as Map);
        final entityType = change['entityType'] as String?;
        if (entityType == 'account' && change['operation'] == 'upsert') {
          final localAccountId = _rewriteAccountId(
            change['entityId'] as String,
            remoteBookId,
            bookId,
          );
          final payload = _rewriteAccountPayload(
            Map<String, dynamic>.from(change['payload'] as Map),
            remoteBookId,
            bookId,
          );
          await _repo.applyRemoteAccountUpsert(
            entityId: localAccountId,
            bookId: bookId,
            payload: payload,
          );
          continue;
        }
        if (entityType != 'transaction') continue;
        if (change['operation'] == 'upsert') {
          final payload = _rewriteTransactionPayload(
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
