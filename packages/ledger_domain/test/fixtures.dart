import 'package:ledger_domain/ledger_domain.dart';

const bookId = BookId('book_1');

final cash = Account(
  id: const AccountId('acc_cash'),
  bookId: bookId,
  name: 'Cash',
  type: AccountType.asset,
  currency: CurrencyCode.cny,
);

final bank = Account(
  id: const AccountId('acc_bank'),
  bookId: bookId,
  name: 'Bank',
  type: AccountType.asset,
  currency: CurrencyCode.cny,
);

final food = Account(
  id: const AccountId('acc_food'),
  bookId: bookId,
  name: 'Food',
  type: AccountType.expense,
  currency: CurrencyCode.cny,
);

final transport = Account(
  id: const AccountId('acc_transport'),
  bookId: bookId,
  name: 'Transport',
  type: AccountType.expense,
  currency: CurrencyCode.cny,
);

final salary = Account(
  id: const AccountId('acc_salary'),
  bookId: bookId,
  name: 'Salary',
  type: AccountType.income,
  currency: CurrencyCode.cny,
);
