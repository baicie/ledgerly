import 'ids.dart';
import 'money.dart';

final class TransactionEntry {
  const TransactionEntry({
    required this.id,
    required this.transactionId,
    required this.accountId,
    required this.amount,
    required this.index,
  });

  final EntryId id;
  final TransactionId transactionId;
  final AccountId accountId;
  final Money amount;
  final int index;
}
