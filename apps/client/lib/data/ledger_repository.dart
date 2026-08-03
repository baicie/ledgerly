import 'package:drift/drift.dart';
import 'package:ledger_domain/ledger_domain.dart' as domain;

import 'database.dart';

class LedgerRepository {
  LedgerRepository(this._db);

  final AppDatabase _db;
  var _seq = 0;

  Future<void> seedIfEmpty() async {
    final books = await _db.select(_db.books).get();
    if (books.isNotEmpty) return;

    const bookId = 'book_default';
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

    await account('acc_cash', 'Cash', 'asset');
    await account('acc_bank', 'Bank', 'asset');
    await account('acc_food', 'Food', 'expense');
    await account('acc_transport', 'Transport', 'expense');
    await account('acc_salary', 'Salary', 'income');
  }

  Future<List<Account>> listAccounts(String bookId) {
    return (_db.select(_db.accounts)..where((t) => t.bookId.equals(bookId)))
        .get();
  }

  Future<List<TransactionSummary>> watchSummariesSync(String bookId) async {
    final txs = await (_db.select(_db.transactions)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();
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
    return entries.fold<BigInt>(
      BigInt.zero,
      (sum, e) => sum + BigInt.parse(e.amountMinor),
    );
  }

  Future<void> saveDomainTransaction(domain.LedgerTransaction tx) async {
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
  });

  final String id;
  final DateTime occurredAt;
  final String? description;
  final int entryCount;
}
