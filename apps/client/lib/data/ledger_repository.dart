import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ledger_domain/ledger_domain.dart' as domain;

import '../domain/ids.dart';
import 'database.dart';

class LedgerRepository {
  LedgerRepository(this._db);

  final AppDatabase _db;
  var _seq = 0;
  static const deviceId = 'device_local_1';

  Future<void> seedIfEmpty() async {
    final books = await _db.select(_db.books).get();
    if (books.isNotEmpty) return;

    final bookId = defaultBookId;
    final now = DateTime.now().toUtc();
    await _db.into(_db.books).insert(
          BooksCompanion.insert(
            id: bookId,
            name: 'Personal',
            currencyCode: 'CNY',
            createdAt: now,
          ),
        );

    Future<void> account(String id, String name, String type) {
      return _db.into(_db.accounts).insert(
            AccountsCompanion.insert(
              id: id,
              bookId: bookId,
              name: name,
              type: type,
              currencyCode: 'CNY',
            ),
          );
    }

    await account(accountKeyCash(bookId), 'Cash', 'asset');
    await account(accountKeyBank(bookId), 'Bank', 'asset');
    await account(accountKeyFood(bookId), 'Food', 'expense');
    await account(accountKeyTransport(bookId), 'Transport', 'expense');
    await account(accountKeySalary(bookId), 'Salary', 'income');

    await _db.into(_db.syncStates).insert(
          SyncStatesCompanion.insert(
            bookId: bookId,
            deviceId: deviceId,
            updatedAt: now,
          ),
        );
  }

  Future<List<Account>> listAccounts(String bookId) {
    return (_db.select(_db.accounts)..where((t) => t.bookId.equals(bookId)))
        .get();
  }

  Future<void> upsertAccount({
    required String id,
    required String bookId,
    required String name,
    required String type,
  }) {
    return _db.into(_db.accounts).insertOnConflictUpdate(
          AccountsCompanion.insert(
            id: id,
            bookId: bookId,
            name: name,
            type: type,
            currencyCode: 'CNY',
          ),
        );
  }

  Future<List<TransactionSummary>> watchSummariesSync(
    String bookId, {
    DateTime? monthStart,
    DateTime? monthEnd,
  }) async {
    final query = _db.select(_db.transactions)
      ..where((t) => t.bookId.equals(bookId) & t.deletedAt.isNull());
    if (monthStart != null) {
      query.where((t) => t.occurredAt.isBiggerOrEqualValue(monthStart));
    }
    if (monthEnd != null) {
      query.where((t) => t.occurredAt.isSmallerThanValue(monthEnd));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    final txs = await query.get();
    final result = <TransactionSummary>[];
    for (final tx in txs) {
      final entries = await (_db.select(_db.transactionEntries)
            ..where((e) => e.transactionId.equals(tx.id)))
          .get();
      result.add(
        TransactionSummary(
          id: tx.id,
          occurredAt: tx.occurredAt,
          description: tx.description,
          entryCount: entries.length,
          version: tx.version,
        ),
      );
    }
    return result;
  }

  Stream<List<TransactionSummary>> watchSummaries(String bookId) {
    return (_db.select(_db.transactions)..where((t) => t.bookId.equals(bookId)))
        .watch()
        .asyncMap((_) => watchSummariesSync(bookId));
  }

  Future<BigInt> accountBalance(String accountId) async {
    final entries = await (_db.select(_db.transactionEntries)
          ..where((e) => e.accountId.equals(accountId)))
        .get();
    // Skip entries whose transaction is deleted.
    var sum = BigInt.zero;
    for (final e in entries) {
      final tx = await (_db.select(_db.transactions)
            ..where((t) => t.id.equals(e.transactionId)))
          .getSingleOrNull();
      if (tx == null || tx.deletedAt != null) continue;
      sum += BigInt.parse(e.amountMinor);
    }
    return sum;
  }

  Future<void> saveDomainTransaction(
    domain.LedgerTransaction tx, {
    required String mutationId,
  }) async {
    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: tx.id.value,
              bookId: tx.bookId.value,
              occurredAt: tx.occurredAt,
              description: Value(tx.description),
              version: Value(tx.version),
              createdAt: DateTime.now().toUtc(),
            ),
          );
      for (final entry in tx.entries) {
        await _db.into(_db.transactionEntries).insert(
              TransactionEntriesCompanion.insert(
                id: entry.id.value,
                transactionId: entry.transactionId.value,
                accountId: entry.accountId.value,
                amountMinor: entry.amount.minorUnits.toString(),
                currencyCode: entry.amount.currency.value,
                entryIndex: entry.index,
              ),
            );
      }
      final payload = {
        'description': tx.description,
        'entries': tx.entries
            .map(
              (e) => {
                'accountId': e.accountId.value,
                'amountMinor': e.amount.minorUnits.toString(),
                'currency': e.amount.currency.value,
              },
            )
            .toList(),
      };
      await _db.into(_db.pendingMutations).insert(
            PendingMutationsCompanion.insert(
              mutationId: mutationId,
              bookId: tx.bookId.value,
              deviceId: deviceId,
              entityType: 'transaction',
              entityId: tx.id.value,
              operation: 'create',
              baseVersion: 0,
              payloadJson: jsonEncode(payload),
              createdAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  Future<void> softDeleteTransaction(String txId, String bookId) async {
    final tx = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    final mutationId = newId();
    await _db.transaction(() async {
      await (_db.update(_db.transactions)..where((t) => t.id.equals(txId)))
          .write(
        TransactionsCompanion(
          deletedAt: Value(DateTime.now().toUtc()),
          version: Value(tx.version + 1),
        ),
      );
      await _db.into(_db.pendingMutations).insert(
            PendingMutationsCompanion.insert(
              mutationId: mutationId,
              bookId: bookId,
              deviceId: deviceId,
              entityType: 'transaction',
              entityId: txId,
              operation: 'delete',
              baseVersion: tx.version,
              payloadJson: jsonEncode({'deleted': true}),
              createdAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  Future<List<PendingMutationRow>> listPending(String bookId) {
    return (_db.select(_db.pendingMutations)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> removePending(String mutationId) async {
    await (_db.delete(_db.pendingMutations)
          ..where((t) => t.mutationId.equals(mutationId)))
        .go();
  }

  Future<SyncState?> syncState(String bookId) {
    return (_db.select(_db.syncStates)..where((t) => t.bookId.equals(bookId)))
        .getSingleOrNull();
  }

  Future<void> updateSyncState({
    required String bookId,
    int? cursor,
    String? accessToken,
    String? refreshToken,
    String? remoteBookId,
    String? lastError,
  }) async {
    final existing = await syncState(bookId);
    if (existing == null) {
      await _db.into(_db.syncStates).insert(
            SyncStatesCompanion.insert(
              bookId: bookId,
              deviceId: deviceId,
              cursor: Value(cursor ?? 0),
              accessToken: Value(accessToken),
              refreshToken: Value(refreshToken),
              remoteBookId: Value(remoteBookId),
              lastError: Value(lastError),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      return;
    }
    await (_db.update(_db.syncStates)..where((t) => t.bookId.equals(bookId)))
        .write(
      SyncStatesCompanion(
        cursor: cursor != null ? Value(cursor) : const Value.absent(),
        accessToken:
            accessToken != null ? Value(accessToken) : const Value.absent(),
        refreshToken:
            refreshToken != null ? Value(refreshToken) : const Value.absent(),
        remoteBookId:
            remoteBookId != null ? Value(remoteBookId) : const Value.absent(),
        lastError: Value(lastError),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> applyRemoteDelete({
    required String entityId,
    required int version,
  }) async {
    await (_db.update(_db.transactions)..where((t) => t.id.equals(entityId)))
        .write(
      TransactionsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        version: Value(version),
      ),
    );
  }

  Future<void> addConflict({
    required String bookId,
    required String entityId,
    required String reason,
    required String localPayloadJson,
    int? remoteVersion,
  }) {
    return _db.into(_db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            id: newId(),
            bookId: bookId,
            entityId: entityId,
            reason: reason,
            localPayloadJson: localPayloadJson,
            remoteVersion: Value(remoteVersion),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<List<SyncConflict>> listConflicts(String bookId) {
    return (_db.select(_db.syncConflicts)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> resolveConflict(String id) async {
    await (_db.delete(_db.syncConflicts)..where((t) => t.id.equals(id))).go();
  }

  Future<void> applyRemoteUpsert({
    required String entityId,
    required String bookId,
    required int version,
    required Map<String, dynamic> payload,
  }) async {
    await _db.transaction(() async {
      await _db.into(_db.transactions).insertOnConflictUpdate(
            TransactionsCompanion.insert(
              id: entityId,
              bookId: bookId,
              occurredAt: DateTime.now().toUtc(),
              description: Value(payload['description'] as String?),
              version: Value(version),
              createdAt: DateTime.now().toUtc(),
              deletedAt: const Value(null),
            ),
          );
      await (_db.delete(_db.transactionEntries)
            ..where((e) => e.transactionId.equals(entityId)))
          .go();
      final entries = (payload['entries'] as List?) ?? const [];
      var index = 0;
      for (final raw in entries) {
        final e = Map<String, dynamic>.from(raw as Map);
        await _db.into(_db.transactionEntries).insert(
              TransactionEntriesCompanion.insert(
                id: '$entityId-$index',
                transactionId: entityId,
                accountId: e['accountId'] as String,
                amountMinor: e['amountMinor'].toString(),
                currencyCode: (e['currency'] as String?) ?? 'CNY',
                entryIndex: index,
              ),
            );
        index++;
      }
    });
  }

  String newId() {
    _seq += 1;
    return 'id_${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }
}

class TransactionSummary {
  TransactionSummary({
    required this.id,
    required this.occurredAt,
    required this.description,
    required this.entryCount,
    this.version = 1,
  });

  final String id;
  final DateTime occurredAt;
  final String? description;
  final int entryCount;
  final int version;
}

typedef PendingMutationRow = PendingMutation;
