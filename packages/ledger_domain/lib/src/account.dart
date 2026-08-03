import 'currency.dart';
import 'ids.dart';

enum AccountType { asset, liability, income, expense, equity }

final class Account {
  const Account({
    required this.id,
    required this.bookId,
    required this.name,
    required this.type,
    required this.currency,
  });

  final AccountId id;
  final BookId bookId;
  final String name;
  final AccountType type;
  final CurrencyCode currency;
}
