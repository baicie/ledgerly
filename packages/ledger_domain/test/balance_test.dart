import 'package:ledger_domain/ledger_domain.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const factory = TransactionFactory();

  test('expense is balanced', () {
    final tx = factory.expense(
      id: const TransactionId('tx1'),
      bookId: bookId,
      occurredAt: DateTime.utc(2026, 8, 1),
      expenseAccount: food,
      fundingAccount: cash,
      amount: Money.fromMinorInt(3000, CurrencyCode.cny),
    );
    expect(tx.entries, hasLength(2));
    expect(
      tx.entries.fold<BigInt>(BigInt.zero, (a, e) => a + e.amount.minorUnits),
      BigInt.zero,
    );
  });

  test('unbalanced raw transaction rejected', () {
    final id = const TransactionId('tx_bad');
    expect(
      () => LedgerTransaction(
        id: id,
        bookId: bookId,
        occurredAt: DateTime.utc(2026, 8, 1),
        entries: [
          TransactionEntry(
            id: const EntryId('e0'),
            transactionId: id,
            accountId: food.id,
            amount: Money.fromMinorInt(100, CurrencyCode.cny),
            index: 0,
          ),
          TransactionEntry(
            id: const EntryId('e1'),
            transactionId: id,
            accountId: cash.id,
            amount: Money.fromMinorInt(-50, CurrencyCode.cny),
            index: 1,
          ),
        ],
      ),
      throwsA(
        isA<DomainException>().having(
          (e) => e.code,
          'code',
          DomainErrorCode.unbalanced,
        ),
      ),
    );
  });

  test('too few entries rejected', () {
    final id = const TransactionId('tx_one');
    expect(
      () => LedgerTransaction(
        id: id,
        bookId: bookId,
        occurredAt: DateTime.utc(2026, 8, 1),
        entries: [
          TransactionEntry(
            id: const EntryId('e0'),
            transactionId: id,
            accountId: food.id,
            amount: Money.fromMinorInt(100, CurrencyCode.cny),
            index: 0,
          ),
        ],
      ),
      throwsA(
        isA<DomainException>().having(
          (e) => e.code,
          'code',
          DomainErrorCode.tooFewEntries,
        ),
      ),
    );
  });
}
