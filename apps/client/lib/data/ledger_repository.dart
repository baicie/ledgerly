import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ledger_domain/ledger_domain.dart' as domain;

import '../domain/ids.dart';
import 'database.dart';

enum ConflictResolution { useRemote, keepLocal }

typedef DeviceIdLoader = Future<String> Function();

class LedgerRepository {
  LedgerRepository(
    this._db, {
    required DeviceIdLoader deviceIdLoader,
  }) : _deviceIdLoader = deviceIdLoader;

  final AppDatabase _db;
  final DeviceIdLoader _deviceIdLoader;
  Future<String>? _deviceId;
  var _seq = 0;

  Future<String> get deviceId => _deviceId ??= _deviceIdLoader();

  Future<void> seedIfEmpty() async {
    final books = await _db.select(_db.books).get();
    final currentDeviceId = await deviceId;
    if (books.isNotEmpty) {
      await _db.update(_db.syncStates).write(
            SyncStatesCompanion(deviceId: Value(currentDeviceId)),
          );
      await _db.update(_db.pendingMutations).write(
            PendingMutationsCompanion(deviceId: Value(currentDeviceId)),
          );
      return;
    }

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
            deviceId: currentDeviceId,
            updatedAt: now,
          ),
        );
  }

  Future<List<Account>> listAccounts(String bookId) {
    return (_db.select(_db.accounts)..where((t) => t.bookId.equals(bookId)))
        .get();
  }

  Future<List<Account>> listCategories(String bookId, String type) {
    return (_db.select(_db.accounts)
          ..where(
            (table) => table.bookId.equals(bookId) & table.type.equals(type),
          )
          ..orderBy([(table) => OrderingTerm.asc(table.name)]))
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

  Future<void> createLocalAccount({
    required String id,
    required String bookId,
    required String name,
    required String type,
    String currencyCode = 'CNY',
  }) async {
    final currentDeviceId = await deviceId;
    final createdAt = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.into(_db.accounts).insert(
            AccountsCompanion.insert(
              id: id,
              bookId: bookId,
              name: name,
              type: type,
              currencyCode: currencyCode,
            ),
          );
      await _queueAccountMutation(
        mutationId: newId(),
        bookId: bookId,
        deviceId: currentDeviceId,
        entityId: id,
        operation: 'create',
        name: name,
        type: type,
        currencyCode: currencyCode,
        createdAt: createdAt,
      );
    });
  }

  Future<void> renameLocalAccount({
    required String id,
    required String name,
  }) async {
    final currentDeviceId = await deviceId;
    await _db.transaction(() async {
      final account = await (_db.select(_db.accounts)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      if (account == null) throw StateError('account not found');

      await (_db.update(_db.accounts)..where((table) => table.id.equals(id)))
          .write(AccountsCompanion(name: Value(name)));
      await _queueAccountMutation(
        mutationId: newId(),
        bookId: account.bookId,
        deviceId: currentDeviceId,
        entityId: account.id,
        operation: 'update',
        name: name,
        type: account.type,
        currencyCode: account.currencyCode,
        createdAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> _queueAccountMutation({
    required String mutationId,
    required String bookId,
    required String deviceId,
    required String entityId,
    required String operation,
    required String name,
    required String type,
    required String currencyCode,
    required DateTime createdAt,
  }) {
    return _db.into(_db.pendingMutations).insert(
          PendingMutationsCompanion.insert(
            mutationId: mutationId,
            bookId: bookId,
            deviceId: deviceId,
            entityType: 'account',
            entityId: entityId,
            operation: operation,
            baseVersion: 0,
            payloadJson: jsonEncode({
              'name': name,
              'accountType': type,
              'currency': currencyCode,
            }),
            createdAt: createdAt,
          ),
        );
  }

  Future<void> applyRemoteAccountUpsert({
    required String entityId,
    required String bookId,
    required Map<String, dynamic> payload,
  }) {
    return _db.into(_db.accounts).insertOnConflictUpdate(
          AccountsCompanion.insert(
            id: entityId,
            bookId: bookId,
            name: payload['name'] as String,
            type: payload['accountType'] as String,
            currencyCode: payload['currency'] as String? ?? 'CNY',
          ),
        );
  }

  Future<List<TransactionSummary>> watchSummariesSync(
    String bookId, {
    DateTime? monthStart,
    DateTime? monthEnd,
  }) async {
    final accounts = await listAccounts(bookId);
    final accountsById = {for (final account in accounts) account.id: account};
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
      final details = _summarizeTransaction(entries, accountsById);
      result.add(
        TransactionSummary(
          id: tx.id,
          occurredAt: tx.occurredAt,
          description: tx.description,
          entryCount: entries.length,
          version: tx.version,
          kind: details.kind,
          amountMinor: details.amountMinor,
          categoryName: details.categoryName,
          accountName: details.accountName,
        ),
      );
    }
    return result;
  }

  _TransactionDetails _summarizeTransaction(
    List<TransactionEntry> entries,
    Map<String, Account> accountsById,
  ) {
    final expenseEntries = entries
        .where((entry) => accountsById[entry.accountId]?.type == 'expense')
        .toList();
    final incomeEntries = entries
        .where((entry) => accountsById[entry.accountId]?.type == 'income')
        .toList();
    final balanceEntries = entries.where((entry) {
      final type = accountsById[entry.accountId]?.type;
      return type == 'asset' || type == 'liability';
    }).toList();

    if (expenseEntries.isNotEmpty) {
      return _TransactionDetails(
        kind: TransactionSummaryKind.expense,
        amountMinor: _absoluteTotal(expenseEntries),
        categoryName: _joinedAccountNames(expenseEntries, accountsById),
        accountName: _firstAccountName(balanceEntries, accountsById),
      );
    }
    if (incomeEntries.isNotEmpty) {
      return _TransactionDetails(
        kind: TransactionSummaryKind.income,
        amountMinor: _absoluteTotal(incomeEntries),
        categoryName: _joinedAccountNames(incomeEntries, accountsById),
        accountName: _firstAccountName(balanceEntries, accountsById),
      );
    }
    if (balanceEntries.length >= 2) {
      final ordered = [...balanceEntries]
        ..sort((a, b) => BigInt.parse(a.amountMinor).compareTo(
              BigInt.parse(b.amountMinor),
            ));
      return _TransactionDetails(
        kind: TransactionSummaryKind.transfer,
        amountMinor: BigInt.parse(ordered.first.amountMinor).abs(),
        categoryName: 'Transfer',
        accountName: ordered
            .map((entry) => accountsById[entry.accountId]?.name)
            .whereType<String>()
            .join(' -> '),
      );
    }
    return _TransactionDetails(
      kind: TransactionSummaryKind.adjustment,
      amountMinor: _absoluteTotal(entries),
      categoryName: null,
      accountName: _firstAccountName(entries, accountsById),
    );
  }

  BigInt _absoluteTotal(List<TransactionEntry> entries) {
    return entries
        .fold<BigInt>(
          BigInt.zero,
          (total, entry) => total + BigInt.parse(entry.amountMinor),
        )
        .abs();
  }

  String? _joinedAccountNames(
    List<TransactionEntry> entries,
    Map<String, Account> accountsById,
  ) {
    final names = entries
        .map((entry) => accountsById[entry.accountId]?.name)
        .whereType<String>()
        .toSet();
    return names.isEmpty ? null : names.join(' + ');
  }

  String? _firstAccountName(
    List<TransactionEntry> entries,
    Map<String, Account> accountsById,
  ) {
    for (final entry in entries) {
      final name = accountsById[entry.accountId]?.name;
      if (name != null) return name;
    }
    return null;
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
    final currentDeviceId = await deviceId;
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
              deviceId: currentDeviceId,
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
    final currentDeviceId = await deviceId;
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
              deviceId: currentDeviceId,
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
    String? remoteBookId,
    String? lastError,
  }) async {
    final existing = await syncState(bookId);
    if (existing == null) {
      await _db.into(_db.syncStates).insert(
            SyncStatesCompanion.insert(
              bookId: bookId,
              deviceId: await deviceId,
              cursor: Value(cursor ?? 0),
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
        deviceId: Value(await deviceId),
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

  Future<void> resolveConflict(
    String id, {
    required ConflictResolution resolution,
  }) async {
    final currentDeviceId =
        resolution == ConflictResolution.keepLocal ? await deviceId : null;
    await _db.transaction(() async {
      final conflict = await (_db.select(_db.syncConflicts)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (conflict == null) return;

      if (resolution == ConflictResolution.keepLocal) {
        final decoded = jsonDecode(conflict.localPayloadJson);
        if (decoded is! Map) {
          throw const FormatException('conflict payload must be a JSON object');
        }
        final operation = decoded['deleted'] == true ? 'delete' : 'update';
        await _db.into(_db.pendingMutations).insert(
              PendingMutationsCompanion.insert(
                mutationId: newId(),
                bookId: conflict.bookId,
                deviceId: currentDeviceId!,
                entityType: 'transaction',
                entityId: conflict.entityId,
                operation: operation,
                baseVersion: conflict.remoteVersion ?? 0,
                payloadJson: conflict.localPayloadJson,
                createdAt: DateTime.now().toUtc(),
              ),
            );
      }
      await (_db.delete(_db.syncConflicts)
            ..where((t) => t.id.equals(conflict.id)))
          .go();
    });
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

enum TransactionSummaryKind { expense, income, transfer, adjustment }

class TransactionSummary {
  TransactionSummary({
    required this.id,
    required this.occurredAt,
    required this.description,
    required this.entryCount,
    this.version = 1,
    this.kind = TransactionSummaryKind.adjustment,
    BigInt? amountMinor,
    this.categoryName,
    this.accountName,
  }) : amountMinor = amountMinor ?? BigInt.zero;

  final String id;
  final DateTime occurredAt;
  final String? description;
  final int entryCount;
  final int version;
  final TransactionSummaryKind kind;
  final BigInt amountMinor;
  final String? categoryName;
  final String? accountName;
}

class _TransactionDetails {
  const _TransactionDetails({
    required this.kind,
    required this.amountMinor,
    required this.categoryName,
    required this.accountName,
  });

  final TransactionSummaryKind kind;
  final BigInt amountMinor;
  final String? categoryName;
  final String? accountName;
}

typedef PendingMutationRow = PendingMutation;
