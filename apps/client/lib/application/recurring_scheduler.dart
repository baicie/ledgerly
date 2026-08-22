import '../data/ledger_repository.dart';
import '../data/local_recurring_repository.dart';
import '../domain/ids.dart';
import 'csv_bill_parser.dart';
import 'ledger_app_service.dart';

class RecurringScheduler {
  RecurringScheduler({
    required LocalRecurringRepository rules,
    required LedgerAppService ledger,
    required LedgerRepository repository,
  })  : _rules = rules,
        _ledger = ledger,
        _repository = repository;

  final LocalRecurringRepository _rules;
  final LedgerAppService _ledger;
  final LedgerRepository _repository;

  Future<int> catchUp({
    String bookId = defaultBookId,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final postedKeys = {
      for (final tx in await _repository.watchSummariesSync(bookId))
        postedRowKey(
          occurredAt: tx.occurredAt,
          amountMinor: tx.amountMinor,
          kind: tx.kind,
          description: tx.description ?? '',
        ),
    };
    var posted = 0;
    for (var i = 0; i < 36; i++) {
      final due = await _rules.due(bookId, clock);
      if (due.isEmpty) break;
      for (final rule in due) {
        final occurredAt = DateTime.parse('${rule.nextRunDate}T12:00:00');
        final kind = rule.kind == 'income'
            ? TransactionSummaryKind.income
            : TransactionSummaryKind.expense;
        final key = postedRowKey(
          occurredAt: occurredAt,
          amountMinor: rule.amountMinor,
          kind: kind,
          description: rule.name,
        );
        if (!postedKeys.contains(key)) {
          await _post(rule);
          postedKeys.add(key);
          posted += 1;
        }
        await _rules.advance(rule);
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
