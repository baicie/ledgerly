import '../data/ledger_repository.dart';
import '../l10n/l10n.dart';
import '../presentation/widgets/ledgerly_finance.dart';

bool matchesFeedQuery(
  TransactionSummary transaction,
  String query,
  AppLocalizations l10n,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final description = (transaction.description ?? '').toLowerCase();
  final category =
      localizedLedgerName(l10n, transaction.categoryName).toLowerCase();
  final account =
      localizedLedgerName(l10n, transaction.accountName).toLowerCase();
  final amount = formatDisplayMinor(transaction.amountMinor).toLowerCase();
  final rawAmount = formatDisplayMinor(
    transaction.amountMinor,
    symbol: false,
  ).toLowerCase();
  return description.contains(needle) ||
      category.contains(needle) ||
      account.contains(needle) ||
      amount.contains(needle) ||
      rawAmount.contains(needle);
}

List<TransactionSummary> filterFeedTransactions(
  Iterable<TransactionSummary> transactions,
  String query,
  AppLocalizations l10n,
) {
  return [
    for (final transaction in transactions)
      if (matchesFeedQuery(transaction, query, l10n)) transaction,
  ];
}
