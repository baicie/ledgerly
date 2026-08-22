import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../application/recurring_date.dart';
import 'database.dart';

class LocalRecurringRule {
  const LocalRecurringRule({
    required this.id,
    required this.bookId,
    required this.name,
    required this.kind,
    required this.amountMinor,
    required this.categoryAccountId,
    required this.accountId,
    required this.dayOfMonth,
    required this.nextRunDate,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String name;
  final String kind;
  final BigInt amountMinor;
  final String categoryAccountId;
  final String accountId;
  final int dayOfMonth;
  final String nextRunDate;
  final bool active;
  final DateTime createdAt;
}

class LocalRecurringRepository {
  LocalRecurringRepository(this._db);

  final AppDatabase _db;

  Future<List<LocalRecurringRule>> list(String bookId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM local_recurring_rules WHERE book_id = ? ORDER BY created_at DESC',
      variables: [Variable<String>(bookId)],
      readsFrom: {},
    ).get();
    return [for (final row in rows) _map(row)];
  }

  Future<List<LocalRecurringRule>> due(String bookId, DateTime now) async {
    final rules = await list(bookId);
    return [
      for (final rule in rules)
        if (rule.active && RecurringDate.isDue(rule.nextRunDate, now)) rule,
    ];
  }

  Future<LocalRecurringRule> insert({
    required String bookId,
    required String name,
    required String kind,
    required BigInt amountMinor,
    required String categoryAccountId,
    required String accountId,
    required int dayOfMonth,
  }) async {
    final day = dayOfMonth.clamp(1, 28);
    final record = LocalRecurringRule(
      id: const Uuid().v4(),
      bookId: bookId,
      name: name,
      kind: kind,
      amountMinor: amountMinor,
      categoryAccountId: categoryAccountId,
      accountId: accountId,
      dayOfMonth: day,
      nextRunDate: RecurringDate.nextMonthlyDate(
        from: DateTime.now(),
        dayOfMonth: day,
      ),
      active: true,
      createdAt: DateTime.now().toUtc(),
    );
    await _db.customStatement(
      '''
INSERT INTO local_recurring_rules
  (id, book_id, name, kind, amount_minor, category_account_id, account_id,
   day_of_month, next_run_date, active, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        record.id,
        record.bookId,
        record.name,
        record.kind,
        record.amountMinor.toString(),
        record.categoryAccountId,
        record.accountId,
        record.dayOfMonth,
        record.nextRunDate,
        record.active ? 1 : 0,
        record.createdAt.millisecondsSinceEpoch,
      ],
    );
    return record;
  }

  Future<void> setActive(String id, bool active) {
    return _db.customStatement(
      'UPDATE local_recurring_rules SET active = ? WHERE id = ?',
      [active ? 1 : 0, id],
    );
  }

  Future<void> advance(LocalRecurringRule rule) {
    return _db.customStatement(
      'UPDATE local_recurring_rules SET next_run_date = ? WHERE id = ?',
      [RecurringDate.advanceOneMonth(rule.nextRunDate, rule.dayOfMonth), rule.id],
    );
  }

  Future<void> delete(String id) {
    return _db.customStatement(
      'DELETE FROM local_recurring_rules WHERE id = ?',
      [id],
    );
  }

  LocalRecurringRule _map(QueryRow row) {
    return LocalRecurringRule(
      id: row.read<String>('id'),
      bookId: row.read<String>('book_id'),
      name: row.read<String>('name'),
      kind: row.read<String>('kind'),
      amountMinor: BigInt.parse(row.read<String>('amount_minor')),
      categoryAccountId: row.read<String>('category_account_id'),
      accountId: row.read<String>('account_id'),
      dayOfMonth: row.read<int>('day_of_month'),
      nextRunDate: row.read<String>('next_run_date'),
      active: row.read<int>('active') == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
    );
  }
}
