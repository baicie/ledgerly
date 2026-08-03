import 'package:ledger_domain/ledger_domain.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const factory = TransactionFactory();

  test('transfer shares transaction id and balances', () {
    final id = const TransactionId('tx_tf');
    final tx = factory.transfer(
      id: id,
      bookId: bookId,
      occurredAt: DateTime.utc(2026, 8, 2),
      from: cash,
      to: bank,
      amount: Money.fromMinorInt(10000, CurrencyCode.cny),
    );
    expect(tx.entries.every((e) => e.transactionId == id), isTrue);
    expect(tx.balanceContribution(cash.id), BigInt.from(-10000));
    expect(tx.balanceContribution(bank.id), BigInt.from(10000));
  });

  test('transfer same account rejected', () {
    expect(
      () => factory.transfer(
        id: const TransactionId('tx_same'),
        bookId: bookId,
        occurredAt: DateTime.utc(2026, 8, 2),
        from: cash,
        to: cash,
        amount: Money.fromMinorInt(100, CurrencyCode.cny),
      ),
      throwsA(
        isA<DomainException>().having(
          (e) => e.code,
          'code',
          DomainErrorCode.invalidTransfer,
        ),
      ),
    );
  });
}
