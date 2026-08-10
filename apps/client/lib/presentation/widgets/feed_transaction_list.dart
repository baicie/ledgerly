import 'package:flutter/material.dart';

import '../../data/ledger_repository.dart';
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
  });

  final List<TransactionSummary> transactions;
  final ValueChanged<TransactionSummary> onOpen;
  final ValueChanged<TransactionSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const SliverToBoxAdapter(
        child: LedgerlyEmptyState(
          icon: Icons.receipt_long_outlined,
          title: '这个月还没有流水',
          message: '点击底部的 +，记下第一笔收支。',
        ),
      );
    }

    final groups = <DateTime, List<TransactionSummary>>{};
    for (final transaction in transactions) {
      final local = transaction.occurredAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      groups.putIfAbsent(day, () => []).add(transaction);
    }

    return SliverList.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final day = groups.keys.elementAt(index);
        final items = groups[day]!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: LedgerlySection(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: PageStorageKey<String>(
                'feed-day-${day.year}-${day.month}-${day.day}',
              ),
              initiallyExpanded: DateUtils.isSameDay(day, DateTime.now()),
              tilePadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateLabel(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当日净额',
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
                for (var itemIndex = 0;
                    itemIndex < items.length;
                    itemIndex++) ...[
                  if (itemIndex > 0) const Divider(indent: 70, endIndent: 16),
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

  String _dateLabel(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
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
    final color = ledgerColorFor(
      transaction.categoryName,
      kind: transaction.kind,
    );
    final category = localizedLedgerName(transaction.categoryName);
    final account = localizedLedgerName(transaction.accountName);
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
            tooltip: '删除流水',
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
