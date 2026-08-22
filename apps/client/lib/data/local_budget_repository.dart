import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'ledger_repository.dart';

class LocalBudgetRecord {
  const LocalBudgetRecord({
    required this.id,
    required this.bookId,
    required this.name,
    required this.amountMinor,
    required this.categoryAccountId,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String name;
  final BigInt amountMinor;
  final String categoryAccountId;
  final DateTime createdAt;
}

class LocalBudgetRepository {
  LocalBudgetRepository(this._db);

  final AppDatabase _db;

  Future<List<LocalBudgetRecord>> list(String bookId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM local_budgets WHERE book_id = ? ORDER BY created_at DESC',
      variables: [Variable<String>(bookId)],
      readsFrom: {},
    ).get();
    return [for (final row in rows) _map(row)];
  }

  Future<LocalBudgetRecord> insert({
    required String bookId,
    required String name,
    required BigInt amountMinor,
    required String categoryAccountId,
  }) async {
    final record = LocalBudgetRecord(
      id: const Uuid().v4(),
      bookId: bookId,
      name: name,
      amountMinor: amountMinor,
      categoryAccountId: categoryAccountId,
      createdAt: DateTime.now().toUtc(),
    );
    await _db.customStatement(
      '''
INSERT INTO local_budgets
  (id, book_id, name, amount_minor, category_account_id, created_at)
VALUES (?, ?, ?, ?, ?, ?)
''',
      [
        record.id,
        record.bookId,
        record.name,
        record.amountMinor.toString(),
        record.categoryAccountId,
        record.createdAt.millisecondsSinceEpoch,
      ],
    );
    return record;
  }

  Future<void> delete(String id) {
    return _db.customStatement(
      'DELETE FROM local_budgets WHERE id = ?',
      [id],
    );
  }

  LocalBudgetRecord _map(QueryRow row) {
    return LocalBudgetRecord(
      id: row.read<String>('id'),
      bookId: row.read<String>('book_id'),
      name: row.read<String>('name'),
      amountMinor: BigInt.parse(row.read<String>('amount_minor')),
      categoryAccountId: row.read<String>('category_account_id'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
    );
  }
}

BigInt spentForBudget({
  required LocalBudgetRecord budget,
  required Iterable<TransactionSummary> transactions,
  required Map<String, String?> parentById,
}) {
  var spent = BigInt.zero;
  for (final tx in transactions) {
    if (tx.kind != TransactionSummaryKind.expense) continue;
    if (!_matchesCategory(
      tx.categoryAccountId ?? '',
      budget.categoryAccountId,
      parentById,
    )) {
      continue;
    }
    spent += tx.amountMinor;
  }
  return spent;
}

bool _matchesCategory(
  String transactionCategoryId,
  String budgetCategoryId,
  Map<String, String?> parentById,
) {
  if (budgetCategoryId.isEmpty) return true;
  var current = transactionCategoryId;
  while (true) {
    if (current == budgetCategoryId) return true;
    final parent = parentById[current];
    if (parent == null || parent.isEmpty) return false;
    current = parent;
  }
}
