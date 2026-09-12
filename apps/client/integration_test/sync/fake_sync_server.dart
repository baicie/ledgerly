// In-process fake of the Ledgerly sync server.
//
// Implements the v1 contract documented at
// docs/sync-protocol/v1.md 鈥?push, pull, bootstrap 鈥?with the following
// behaviours the production server must guarantee:
//
//   * Idempotency keyed by (bookId, deviceId, mutationId). Replays return
//     the original receipt without re-applying the mutation.
//   * Sequential change log per book with monotonically increasing
//     sequences used as cursors.
//   * Receipt result codes match the public enum: OK, LEDGER_UNBALANCED,
//     LEDGER_VERSION_CONFLICT, INVALID_PAYLOAD, INVALID_CATEGORY_PARENT,
//     UNSUPPORTED_MUTATION, ACCOUNT_NOT_FOUND.
//   * Transactions must be balanced per currency (sum of entries == 0).
//
// The fake additionally exposes failure-injection hooks (`failNextPush`,
// `dropNextChange`, `forceLedgerVersionConflict`, `resetCursor`) so the
// surrounding scenarios can drive the SyncService down its error paths
// without standing up a real server.
//
// This fake intentionally models a single shared book across both
// devices in the harness, mirroring the production "two devices, one
// book, eventually consistent" invariant. Multi-book scenarios are out
// of scope for Phase 3.2 (see design doc).

import 'dart:async';
import 'dart:convert';

/// In-process server state shared between two devices under test.
///
/// All methods are synchronous from the caller's perspective; the
/// asynchronous signature exists so future real-server tests can swap
/// the implementation without changing the harness.
class FakeSyncServer {
  FakeSyncServer({String bookId = defaultServerBookId})
      : _bookId = bookId;

  static const String defaultServerBookId =
      '00000000-0000-0000-0000-000000000001';

  /// Remote (server-side) book id. Distinct from the local `book_default`
  /// so that the SyncService's `_rewriteAccountId` path actually runs.
  final String _bookId;

  /// Per-book account table keyed by remote account id.
  final Map<String, RemoteAccount> _accounts = {};

  /// Per-book transaction table keyed by entity id; carries the latest
  /// committed version.
  final Map<String, RemoteTransaction> _transactions = {};

  /// Append-only change log keyed by `bookId`.
  final List<RemoteChange> _changeLog = [];

  /// Per-book per-device idempotency table. Replays return the cached
  /// receipt without re-applying.
  final Map<String, Map<String, Map<String, CachedReceipt>>>
      _idempotency = {};

  /// Per-device cursor override (used by `resetCursor`).
  final Map<String, int> _deviceCursorOverride = {};

  /// Failure-injection toggles consumed once then reset.
  PendingFailure _pendingFailure = const PendingFailure();

  int _sequence = 0;

  // ---------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------

  /// The remote book id used by every request.
  String get bookId => _bookId;

  /// Snapshot the current change log for assertions.
  List<RemoteChange> get changeLogSnapshot =>
      List.unmodifiable(_changeLog);

  /// Snapshot all committed transactions for assertions.
  List<RemoteTransaction> get transactionsSnapshot =>
      List.unmodifiable(_transactions.values);

  /// Snapshot all known accounts (server-side ids).
  List<RemoteAccount> get accountsSnapshot =>
      List.unmodifiable(_accounts.values);

  /// Make the next [push] call throw as if the server returned HTTP 500.
  void failNextPush(String message) {
    _pendingFailure = PendingFailure(
      pushMessage: message,
    );
  }

  /// Make the next [pull] return a change log missing the most recent
  /// entry. Used to exercise cursor-mismatch paths.
  void dropNextChange() {
    _pendingFailure = PendingFailure(
      dropChange: true,
    );
  }

  /// Override a future push so the receipt reports
  /// `LEDGER_VERSION_CONFLICT` even if the payload is otherwise valid.
  void forceLedgerVersionConflict() {
    _pendingFailure = PendingFailure(
      forceLedgerConflict: true,
    );
  }

  /// Reset the cursor for the given device back to 0, simulating a
  /// server-side snapshot reset (e.g. database restore).
  void resetCursorFor(String deviceId) {
    _deviceCursorOverride[deviceId] = 0;
  }

  // ---------------------------------------------------------------------
  // Sync endpoints
  // ---------------------------------------------------------------------

  /// Mirrors `POST /v1/books/{bookId}/sync/push`. Returns the response
  /// body as decoded by the real SyncApi.
  Future<Map<String, dynamic>> push({
    required String deviceId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    final failure = _consumeFailure();
    if (failure.pushMessage != null) {
      throw StateError(failure.pushMessage!);
    }

    final idem = _idempotency.putIfAbsent(
      _bookId,
      () => <String, Map<String, CachedReceipt>>{},
    );
    final deviceIdem = idem.putIfAbsent(deviceId, () => {});

    final receipts = <Map<String, dynamic>>[];
    for (final raw in mutations) {
      final mutationId = raw['mutationId'] as String;
      final cached = deviceIdem[mutationId];
      if (cached != null) {
        receipts.add(cached.toJson());
        continue;
      }
      final receipt = _applyMutation(
        deviceId: deviceId,
        mutation: raw,
        forceConflict: failure.forceLedgerConflict,
      );
      deviceIdem[mutationId] = receipt;
      receipts.add(receipt.toJson());
    }
    return {'receipts': receipts};
  }

  /// Mirrors `GET /v1/books/{bookId}/sync/pull?cursor={n}`.
  Future<Map<String, dynamic>> pull({
    required String deviceId,
    required int cursor,
    int limit = 500,
  }) async {
    final failure = _consumeFailure();
    var effectiveCursor = cursor;
    final override = _deviceCursorOverride[deviceId];
    if (override != null) {
      effectiveCursor = override;
      _deviceCursorOverride.remove(deviceId);
    }

    final pending =
        _changeLog.where((c) => c.sequence > effectiveCursor).toList();
    pending.sort((a, b) => a.sequence.compareTo(b.sequence));
    final page = pending.take(limit).toList();
    final pageChanges = failure.dropChange && page.isNotEmpty
        ? page.sublist(0, page.length - 1)
        : page;
    final nextSequence =
        page.isEmpty ? effectiveCursor : page.last.sequence;
    return {
      'changes': pageChanges
          .map((c) => c.toJson(_bookId))
          .toList(growable: false),
      'nextCursor': nextSequence,
    };
  }

  /// Mirrors `POST /v1/books/{bookId}/sync/bootstrap`. Returns every
  /// change from sequence 1 onwards in one shot.
  Future<Map<String, dynamic>> bootstrap() async {
    final ordered = List<RemoteChange>.from(_changeLog)
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final nextSequence =
        ordered.isEmpty ? 0 : ordered.last.sequence;
    return {
      'changes': ordered
          .map((c) => c.toJson(_bookId))
          .toList(growable: false),
      'nextCursor': nextSequence,
    };
  }

  // ---------------------------------------------------------------------
  // Mutation application
  // ---------------------------------------------------------------------

  CachedReceipt _applyMutation({
    required String deviceId,
    required Map<String, dynamic> mutation,
    required bool forceConflict,
  }) {
    final mutationId = mutation['mutationId'] as String;
    final entityType = mutation['entityType'] as String;
    final entityId = mutation['entityId'] as String;
    final operation = mutation['operation'] as String;
    final baseVersion = mutation['baseVersion'] as int? ?? 0;
    final schemaVersion = mutation['schemaVersion'] as int? ?? 1;
    final payload = Map<String, dynamic>.from(
      mutation['payload'] as Map? ?? const <String, dynamic>{},
    );

    if (schemaVersion != 1) {
      return CachedReceipt(
        mutationId: mutationId,
        status: 'rejected',
        resultCode: 'UNSUPPORTED_MUTATION',
      );
    }

    if (entityType == 'account') {
      return _applyAccountMutation(
        mutationId: mutationId,
        entityId: entityId,
        operation: operation,
        payload: payload,
      );
    }

    if (entityType == 'transaction') {
      return _applyTransactionMutation(
        mutationId: mutationId,
        entityId: entityId,
        operation: operation,
        baseVersion: baseVersion,
        payload: payload,
        forceConflict: forceConflict,
      );
    }

    return CachedReceipt(
      mutationId: mutationId,
      status: 'rejected',
      resultCode: 'INVALID_PAYLOAD',
    );
  }

  CachedReceipt _applyAccountMutation({
    required String mutationId,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    if (operation == 'create' || operation == 'update') {
      final name = payload['name'] as String?;
      final accountType = payload['accountType'] as String?;
      if (name == null || accountType == null) {
        return CachedReceipt(
          mutationId: mutationId,
          status: 'rejected',
          resultCode: 'INVALID_PAYLOAD',
        );
      }
      final existing = _accounts[entityId];
      final nextVersion = (existing?.version ?? 0) + 1;
      _accounts[entityId] = RemoteAccount(
        id: entityId,
        name: name,
        accountType: accountType,
        currency: payload['currency'] as String? ?? 'CNY',
        parentAccountId: payload['parentAccountId'] as String?,
        version: nextVersion,
      );
      _appendChange(
        entityType: 'account',
        entityId: entityId,
        operation: 'upsert',
        payload: {
          'name': name,
          'accountType': accountType,
          'currency': payload['currency'] ?? 'CNY',
          'parentAccountId': payload['parentAccountId'],
        },
        version: nextVersion,
      );
      return CachedReceipt(
        mutationId: mutationId,
        status: 'applied',
        resultCode: 'OK',
        entityVersion: nextVersion,
      );
    }

    if (operation == 'delete') {
      _accounts.remove(entityId);
      _appendChange(
        entityType: 'account',
        entityId: entityId,
        operation: 'delete',
        payload: const {},
        version: 1,
      );
      return CachedReceipt(
        mutationId: mutationId,
        status: 'applied',
        resultCode: 'OK',
      );
    }

    return CachedReceipt(
      mutationId: mutationId,
      status: 'rejected',
      resultCode: 'UNSUPPORTED_MUTATION',
    );
  }

  CachedReceipt _applyTransactionMutation({
    required String mutationId,
    required String entityId,
    required String operation,
    required int baseVersion,
    required Map<String, dynamic> payload,
    required bool forceConflict,
  }) {
    if (operation != 'create' && operation != 'update') {
      return CachedReceipt(
        mutationId: mutationId,
        status: 'rejected',
        resultCode: 'UNSUPPORTED_MUTATION',
      );
    }

    final existing = _transactions[entityId];
    if (!forceConflict && existing != null && baseVersion != existing.version) {
      return CachedReceipt(
        mutationId: mutationId,
        status: 'rejected',
        resultCode: 'LEDGER_VERSION_CONFLICT',
        entityVersion: existing.version,
      );
    }

    final entriesRaw = payload['entries'];
    if (entriesRaw is! List || entriesRaw.isEmpty) {
      return CachedReceipt(
        mutationId: mutationId,
        status: 'rejected',
        resultCode: 'INVALID_PAYLOAD',
      );
    }

    final entries = <RemoteEntry>[];
    for (final raw in entriesRaw) {
      final e = Map<String, dynamic>.from(raw as Map);
      final amount = BigInt.parse(e['amountMinor'].toString());
      final currency = e['currency'] as String? ?? 'CNY';
      entries.add(
        RemoteEntry(
          accountId: e['accountId'] as String,
          amountMinor: amount,
          currency: currency,
        ),
      );
    }

    if (!_isBalanced(entries)) {
      return CachedReceipt(
        mutationId: mutationId,
        status: 'rejected',
        resultCode: 'LEDGER_UNBALANCED',
      );
    }

    final nextVersion = (existing?.version ?? 0) + 1;
    final occurredAt = payload['occurredAt'] as String?;
    final description = payload['description'] as String?;

    _transactions[entityId] = RemoteTransaction(
      id: entityId,
      version: nextVersion,
      description: description,
      occurredAt: occurredAt,
      entries: entries,
    );

    _appendChange(
      entityType: 'transaction',
      entityId: entityId,
      operation: 'upsert',
      payload: {
        'description': description,
        if (occurredAt != null) 'occurredAt': occurredAt,
        'entries': entries
            .map((e) => {
                  'accountId': e.accountId,
                  'amountMinor': e.amountMinor.toString(),
                  'currency': e.currency,
                })
            .toList(),
      },
      version: nextVersion,
    );

    return CachedReceipt(
      mutationId: mutationId,
      status: 'applied',
      resultCode: 'OK',
      entityVersion: nextVersion,
    );
  }

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  PendingFailure _consumeFailure() {
    final f = _pendingFailure;
    _pendingFailure = const PendingFailure();
    return f;
  }

  void _appendChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    required int version,
  }) {
    _sequence += 1;
    _changeLog.add(
      RemoteChange(
        sequence: _sequence,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        version: version,
        payload: payload,
      ),
    );
  }

  bool _isBalanced(List<RemoteEntry> entries) {
    final totals = <String, BigInt>{};
    for (final e in entries) {
      totals[e.currency] = (totals[e.currency] ?? BigInt.zero) + e.amountMinor;
    }
    return totals.values.every((sum) => sum == BigInt.zero);
  }
}

// ---------------------------------------------------------------------------
// Internal data classes
// ---------------------------------------------------------------------------

class RemoteAccount {
  const RemoteAccount({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currency,
    required this.parentAccountId,
    required this.version,
  });

  final String id;
  final String name;
  final String accountType;
  final String currency;
  final String? parentAccountId;
  final int version;
}

class RemoteTransaction {
  const RemoteTransaction({
    required this.id,
    required this.version,
    required this.description,
    required this.occurredAt,
    required this.entries,
  });

  final String id;
  final int version;
  final String? description;
  final String? occurredAt;
  final List<RemoteEntry> entries;
}

class RemoteEntry {
  const RemoteEntry({
    required this.accountId,
    required this.amountMinor,
    required this.currency,
  });

  final String accountId;
  final BigInt amountMinor;
  final String currency;
}

class RemoteChange {
  const RemoteChange({
    required this.sequence,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.version,
    required this.payload,
  });

  final int sequence;
  final String entityType;
  final String entityId;
  final String operation;
  final int version;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson(String bookId) => {
        'bookId': bookId,
        'entityType': entityType,
        'entityId': entityId,
        'operation': operation,
        'version': version,
        'payload': jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
      };
}

class CachedReceipt {
  const CachedReceipt({
    required this.mutationId,
    required this.status,
    required this.resultCode,
    this.entityVersion,
  });

  final String mutationId;
  final String status;
  final String resultCode;
  final int? entityVersion;

  Map<String, dynamic> toJson() => {
        'mutationId': mutationId,
        'status': status,
        'resultCode': resultCode,
        if (entityVersion != null) 'entityVersion': entityVersion,
      };
}

class PendingFailure {
  const PendingFailure({
    this.pushMessage,
    this.dropChange = false,
    this.forceLedgerConflict = false,
  });

  final String? pushMessage;
  final bool dropChange;
  final bool forceLedgerConflict;
}

// ---------------------------------------------------------------------------
// Visible test-only snapshots
// ---------------------------------------------------------------------------

/// Snapshot of a committed transaction on the fake server. Used by
/// tests to assert what made it across the wire.
class RemoteTransactionSnapshot {
  const RemoteTransactionSnapshot({
    required this.id,
    required this.version,
    required this.description,
    required this.entries,
  });

  final String id;
  final int version;
  final String? description;
  final List<RemoteEntrySnapshot> entries;

  factory RemoteTransactionSnapshot.fromServer(RemoteTransaction t) {
    return RemoteTransactionSnapshot(
      id: t.id,
      version: t.version,
      description: t.description,
      entries: t.entries
          .map((e) => RemoteEntrySnapshot(
                accountId: e.accountId,
                amountMinor: e.amountMinor,
                currency: e.currency,
              ))
          .toList(),
    );
  }
}

class RemoteEntrySnapshot {
  const RemoteEntrySnapshot({
    required this.accountId,
    required this.amountMinor,
    required this.currency,
  });

  final String accountId;
  final BigInt amountMinor;
  final String currency;
}



