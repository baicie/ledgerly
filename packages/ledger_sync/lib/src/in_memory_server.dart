import 'mutation.dart';

/// Minimal authoritative sync node for dual-device tests.
class InMemorySyncServer {
  final Map<String, MutationReceipt> _receipts = {};
  final List<SyncChange> _changes = [];
  final Map<String, Map<String, Object?>> _entities = {};
  var _seq = 0;

  List<MutationReceipt> push({
    required String bookId,
    required String deviceId,
    required List<PendingMutation> mutations,
  }) {
    final out = <MutationReceipt>[];
    for (final m in mutations) {
      final key = '$bookId|$deviceId|${m.mutationId}';
      if (_receipts.containsKey(key)) {
        out.add(_receipts[key]!);
        continue;
      }
      final receipt = _apply(bookId, m);
      _receipts[key] = receipt;
      out.add(receipt);
    }
    return out;
  }

  MutationReceipt _apply(String bookId, PendingMutation m) {
    if (m.entityType != 'transaction' || m.operation != 'create') {
      return MutationReceipt(
        mutationId: m.mutationId,
        status: 'rejected',
        resultCode: 'UNSUPPORTED_MUTATION',
      );
    }
    final entries = (m.payload['entries'] as List?) ?? const [];
    var sum = BigInt.zero;
    for (final e in entries) {
      final map = Map<String, Object?>.from(e as Map);
      sum += BigInt.parse(map['amountMinor']! as String);
    }
    if (entries.length < 2 || sum != BigInt.zero) {
      return MutationReceipt(
        mutationId: m.mutationId,
        status: 'rejected',
        resultCode: 'LEDGER_UNBALANCED',
      );
    }
    final existing = _entities[m.entityId];
    if (existing != null) {
      final version = existing['version'] as int;
      if (m.baseVersion != 0 && m.baseVersion != version) {
        return MutationReceipt(
          mutationId: m.mutationId,
          status: 'rejected',
          resultCode: 'LEDGER_VERSION_CONFLICT',
          entityVersion: version,
        );
      }
    }
    const version = 1;
    _entities[m.entityId] = {
      'bookId': bookId,
      'version': version,
      'payload': m.payload,
    };
    _seq += 1;
    final commitId = 'commit_$_seq';
    _changes.add(
      SyncChange(
        sequence: _seq,
        commitId: commitId,
        entityType: m.entityType,
        entityId: m.entityId,
        operation: 'upsert',
        version: version,
        payload: m.payload,
      ),
    );
    return MutationReceipt(
      mutationId: m.mutationId,
      status: 'applied',
      resultCode: 'OK',
      entityVersion: version,
    );
  }

  ({List<SyncChange> changes, int nextCursor, bool hasMore}) pull({
    required String bookId,
    required int cursor,
    int limit = 500,
  }) {
    final filtered = _changes.where((c) => c.sequence > cursor).toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final page = <SyncChange>[];
    String? lastCommit;
    for (final c in filtered) {
      if (page.length >= limit) {
        if (lastCommit == c.commitId) {
          page.add(c);
          continue;
        }
        break;
      }
      lastCommit = c.commitId;
      page.add(c);
    }
    final next = page.isEmpty ? cursor : page.last.sequence;
    final hasMore = _changes.any((c) => c.sequence > next);
    return (changes: page, nextCursor: next, hasMore: hasMore);
  }
}
