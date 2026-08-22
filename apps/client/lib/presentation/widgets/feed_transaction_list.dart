import 'package:flutter/material.dart';

import '../../data/ledger_repository.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import 'ledgerly_finance.dart';
import 'ledgerly_layout.dart';

BigInt dailyNetMinor(Iterable<TransactionSummary> transactions) {
  var net = BigInt.zero;
  for (final transaction in transactions) {
    switch (transaction.kind) {
      case TransactionSummaryKind.income:
        net += transaction.amountMinor;
      case TransactionSummaryKind.expense:
        net -= transaction.amountMinor;
      case TransactionSummaryKind.transfer:
      case TransactionSummaryKind.adjustment:
        break;
    }
  }
  return net;
}

class FeedTransactionList extends StatelessWidget {
  const FeedTransactionList({
    super.key,
    required this.transactions,
    required this.onOpen,
    required this.onDelete,
    this.todayInsight,
    this.orphanTodayInsight = true,
  });

  final List<TransactionSummary> transactions;
  final ValueChanged<TransactionSummary> onOpen;
  final ValueChanged<TransactionSummary> onDelete;
  final Widget? todayInsight;

  /// Pin [todayInsight] above the list when today has no transactions.
  final bool orphanTodayInsight;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    if (transactions.isEmpty) {
      return SliverToBoxAdapter(
        child: Column(
          children: [
            if (todayInsight != null && orphanTodayInsight)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: LedgerlySection(
                  padding: EdgeInsets.zero,
                  child: todayInsight!,
                ),
              ),
            LedgerlyEmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.emptyMonthTitle,
              message: l10n.emptyMonthMessage,
            ),
          ],
        ),
      );
    }

    final groups = <DateTime, List<TransactionSummary>>{};
    for (final transaction in transactions) {
      final local = transaction.occurredAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      groups.putIfAbsent(day, () => []).add(transaction);
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final days = groups.keys.toList();
    final hasToday = days.any((day) => DateUtils.isSameDay(day, today));
    final showOrphanToday =
        todayInsight != null && orphanTodayInsight && !hasToday;

    return SliverList.builder(
      itemCount: days.length + (showOrphanToday ? 1 : 0),
      itemBuilder: (context, index) {
        if (showOrphanToday && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LedgerlySection(
              padding: EdgeInsets.zero,
              child: todayInsight!,
            ),
          );
        }
        final day = days[showOrphanToday ? index - 1 : index];
        final items = groups[day]!;
        final isToday = DateUtils.isSameDay(day, today);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: LedgerlySection(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: PageStorageKey<String>(
                'feed-day-${day.year}-${day.month}-${day.day}',
              ),
              initiallyExpanded: isToday,
              tilePadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.feedDayLabel(
                        day.month,
                        day.day,
                        weekdayLabel(l10n, day.weekday),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.dayNet,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _dailyNetLabel(items),
                        maxLines: 1,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _dailyNetColor(items),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                if (isToday && todayInsight != null) todayInsight!,
                for (var itemIndex = 0;
                    itemIndex < items.length;
                    itemIndex++) ...[
                  if (itemIndex > 0 || (isToday && todayInsight != null))
                    const Divider(indent: 70, endIndent: 16),
                  _TransactionTile(
                    transaction: items[itemIndex],
                    onTap: items[itemIndex].kind ==
                            TransactionSummaryKind.adjustment
                        ? null
                        : () => onOpen(items[itemIndex]),
                    onDelete: () => onDelete(items[itemIndex]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _dailyNetLabel(List<TransactionSummary> transactions) {
    final net = dailyNetMinor(transactions);
    final prefix = net > BigInt.zero ? '+' : '';
    return '$prefix${formatDisplayMinor(net)}';
  }

  Color _dailyNetColor(List<TransactionSummary> transactions) {
    final net = dailyNetMinor(transactions);
    if (net > BigInt.zero) return LedgerlyColors.income;
    if (net < BigInt.zero) return LedgerlyColors.expense;
    return LedgerlyColors.muted;
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.onTap,
    required this.onDelete,
  });

  final TransactionSummary transaction;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final color = ledgerColorFor(
      transaction.categoryName,
      kind: transaction.kind,
    );
    final category = localizedLedgerName(l10n, transaction.categoryName);
    final account = localizedLedgerName(l10n, transaction.accountName);
    final localTime = transaction.occurredAt.toLocal();

    return ListTile(
      key: ValueKey('transaction-${transaction.id}'),
      onTap: onTap,
      minTileHeight: 76,
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      leading: LedgerlyIconBadge(
        icon: ledgerIconFor(transaction.categoryName, kind: transaction.kind),
        color: color,
      ),
      title: Text(
        transaction.description?.trim().isNotEmpty == true
            ? transaction.description!
            : category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$category · $account · ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _amountLabel(transaction),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: l10n.deleteTransaction,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: LedgerlyColors.muted,
          ),
        ],
      ),
    );
  }

  String _amountLabel(TransactionSummary transaction) {
    final prefix = switch (transaction.kind) {
      TransactionSummaryKind.expense => '-',
      TransactionSummaryKind.income => '+',
      TransactionSummaryKind.transfer => '',
      TransactionSummaryKind.adjustment => '',
    };
    return '$prefix${formatDisplayMinor(transaction.amountMinor)}';
  }
}
