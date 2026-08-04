import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/presentation/providers.dart';

void main() {
  test('monthly report aggregates expense categories and ledger totals',
      () async {
    final transactions = [
      _summary(
        id: 'expense-food-1',
        kind: TransactionSummaryKind.expense,
        amountMinor: 4200,
        category: 'Food',
      ),
      _summary(
        id: 'income-salary',
        kind: TransactionSummaryKind.income,
        amountMinor: 10000,
        category: 'Salary',
      ),
      _summary(
        id: 'expense-transport',
        kind: TransactionSummaryKind.expense,
        amountMinor: 2000,
        category: 'Transport',
      ),
      _summary(
        id: 'expense-food-2',
        kind: TransactionSummaryKind.expense,
        amountMinor: 1300,
        category: 'Food',
      ),
      _summary(
        id: 'transfer',
        kind: TransactionSummaryKind.transfer,
        amountMinor: 500,
        category: 'Transfer',
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        monthTransactionsProvider.overrideWith((ref) async => transactions),
        accountBalancesProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);

    final categories = await container.read(categoryReportProvider.future);
    final summary = await container.read(monthlyLedgerSummaryProvider.future);

    expect(categories.map((row) => row.name), ['Food', 'Transport']);
    expect(categories.map((row) => row.amount), [
      BigInt.from(5500),
      BigInt.from(2000),
    ]);
    expect(categories.map((row) => row.transactionCount), [2, 1]);
    expect(summary.incomeMinor, BigInt.from(10000));
    expect(summary.expenseMinor, BigInt.from(7500));
    expect(summary.balanceMinor, BigInt.from(2500));
    expect(summary.transactionCount, 5);
  });
}

TransactionSummary _summary({
  required String id,
  required TransactionSummaryKind kind,
  required int amountMinor,
  required String category,
}) {
  return TransactionSummary(
    id: id,
    occurredAt: DateTime.utc(2026, 8, 4),
    description: id,
    entryCount: 2,
    kind: kind,
    amountMinor: BigInt.from(amountMinor),
    categoryName: category,
    accountName: 'Cash',
  );
}
