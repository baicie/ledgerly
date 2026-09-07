import '../data/ledger_repository.dart';
import '../l10n/l10n.dart';
import '../presentation/widgets/ledgerly_finance.dart';

/// Restricts the feed view to a subset of transactions based on provenance.
///
/// The values are stable strings so they can survive serialization if the
/// filter chip's selected state is ever persisted.
enum FeedSourceFilter {
  all('all'),
  autoLedger('auto_ledger'),
  manual('manual');

  const FeedSourceFilter(this.tag);

  /// The opaque tag used on the underlying [TransactionSummary.source] field.
  /// `null` matches transactions that have no source tag (treated as manual).
  final String tag;

  static FeedSourceFilter fromTag(String? tag) {
    for (final value in values) {
      if (value.tag == tag) return value;
    }
    return FeedSourceFilter.all;
  }
}

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

bool matchesFeedSource(TransactionSummary transaction, FeedSourceFilter filter) {
  switch (filter) {
    case FeedSourceFilter.all:
      return true;
    case FeedSourceFilter.autoLedger:
      return transaction.isAutoLedger;
    case FeedSourceFilter.manual:
      // A null source is treated as manual: legacy rows pre-dating the field
      // and rows typed in by users both lack a source tag.
      return !transaction.isAutoLedger;
  }
}

List<TransactionSummary> filterFeedTransactions(
  Iterable<TransactionSummary> transactions,
  String query,
  AppLocalizations l10n, {
  FeedSourceFilter sourceFilter = FeedSourceFilter.all,
}) {
  return [
    for (final transaction in transactions)
      if (matchesFeedQuery(transaction, query, l10n) &&
          matchesFeedSource(transaction, sourceFilter))
        transaction,
  ];
}
