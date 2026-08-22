import '../data/local_recurring_repository.dart';
import '../domain/ids.dart';
import 'ledger_app_service.dart';

class RecurringScheduler {
  RecurringScheduler({
    required LocalRecurringRepository rules,
    required LedgerAppService ledger,
  })  : _rules = rules,
        _ledger = ledger;

  final LocalRecurringRepository _rules;
  final LedgerAppService _ledger;

  Future<int> catchUp({
    String bookId = defaultBookId,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    var posted = 0;
    for (var i = 0; i < 36; i++) {
      final due = await _rules.due(bookId, clock);
      if (due.isEmpty) break;
      for (final rule in due) {
        await _post(rule);
        await _rules.advance(rule);
        posted += 1;
      }
    }
    return posted;
  }

  Future<void> _post(LocalRecurringRule rule) {
    final occurredAt = DateTime.parse('${rule.nextRunDate}T12:00:00');
    if (rule.kind == 'income') {
      return _ledger.createIncome(
        incomeAccountId: rule.categoryAccountId,
        depositAccountId: rule.accountId,
        amountMinor: rule.amountMinor,
        description: rule.name,
        occurredAt: occurredAt,
      );
    }
    return _ledger.createExpense(
      expenseAccountId: rule.categoryAccountId,
      fundingAccountId: rule.accountId,
      amountMinor: rule.amountMinor,
      description: rule.name,
      occurredAt: occurredAt,
    );
  }
}
