import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/presentation/widgets/feed_transaction_list.dart';

void main() {
  test('daily total is negative when a day only has expenses', () {
    final total = dailyNetMinor([
      _summary(TransactionSummaryKind.expense, 4200),
      _summary(TransactionSummaryKind.expense, 1800),
    ]);

    expect(total, BigInt.from(-6000));
  });

  test('daily total subtracts expenses from income', () {
    final total = dailyNetMinor([
      _summary(TransactionSummaryKind.income, 10000),
      _summary(TransactionSummaryKind.expense, 2500),
    ]);

    expect(total, BigInt.from(7500));
  });
}

TransactionSummary _summary(TransactionSummaryKind kind, int amountMinor) {
  return TransactionSummary(
    id: '$kind-$amountMinor',
    occurredAt: DateTime.utc(2026, 8, 4),
    description: 'test',
    entryCount: 2,
    kind: kind,
    amountMinor: BigInt.from(amountMinor),
  );
}
