import 'package:ledger_domain/ledger_domain.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const factory = TransactionFactory();

  test('split expense balances across lines', () {
    final tx = factory.splitExpense(
      id: const TransactionId('tx_split'),
      bookId: bookId,
      occurredAt: DateTime.utc(2026, 8, 3),
      fundingAccount: cash,
      splits: [
        (account: food, amount: Money.fromMinorInt(2000, CurrencyCode.cny)),
        (account: transport, amount: Money.fromMinorInt(1500, CurrencyCode.cny)),
      ],
    );
    expect(tx.entries, hasLength(3));
    expect(
      tx.entries.fold<BigInt>(BigInt.zero, (a, e) => a + e.amount.minorUnits),
      BigInt.zero,
    );
    expect(tx.balanceContribution(cash.id), BigInt.from(-3500));
  });

  test('refund reverses expense direction', () {
    final tx = factory.refundExpense(
      id: const TransactionId('tx_refund'),
      bookId: bookId,
      occurredAt: DateTime.utc(2026, 8, 4),
      expenseAccount: food,
      refundToAccount: cash,
      amount: Money.fromMinorInt(500, CurrencyCode.cny),
    );
    expect(tx.balanceContribution(cash.id), BigInt.from(500));
    expect(tx.balanceContribution(food.id), BigInt.from(-500));
  });

  test('income is balanced', () {
    final tx = factory.income(
      id: const TransactionId('tx_inc'),
      bookId: bookId,
      occurredAt: DateTime.utc(2026, 8, 5),
      incomeAccount: salary,
      depositAccount: bank,
      amount: Money.fromMinorInt(100000, CurrencyCode.cny),
    );
    expect(
      tx.entries.fold<BigInt>(BigInt.zero, (a, e) => a + e.amount.minorUnits),
      BigInt.zero,
    );
  });
}
