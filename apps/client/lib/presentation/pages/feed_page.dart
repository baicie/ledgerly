import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../widgets/feed_transaction_list.dart';
import '../widgets/ledgerly_layout.dart';
import '../widgets/ledgerly_summary_card.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final transactions = ref.watch(monthTransactionsProvider);
    final summary = ref.watch(monthlyLedgerSummaryProvider);
    final hasRemote = ref.watch(apiEndpointProvider) != null;

    return Scaffold(
      body: SafeArea(
        child: LedgerlyContent(
          slivers: [
            const SliverToBoxAdapter(
              child: LedgerlyPageHeader(
                title: '全部流水',
                subtitle: '标准账本',
              ),
            ),
            SliverToBoxAdapter(
              child: LedgerlyMonthPicker(
                month: month,
                onPrevious: () => _changeMonth(ref, month, -1),
                onNext: () => _changeMonth(ref, month, 1),
              ),
            ),
            summary.when(
              skipLoadingOnReload: true,
              data: (totals) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                sliver: SliverToBoxAdapter(
                  child: LedgerlySummaryCard(
                    title: '本月流水统计',
                    balanceMinor: totals.balanceMinor,
                    incomeMinor: totals.incomeMinor,
                    expenseMinor: totals.expenseMinor,
                  ),
                ),
              ),
              loading: () => const _FeedLoading(),
              error: (error, _) => _FeedError(error: error),
            ),
            transactions.when(
              skipLoadingOnReload: true,
              data: (items) => FeedTransactionList(
                transactions: items,
                hasRemote: hasRemote,
                onOpen: (transaction) => context.go(
                  '/feed/revisions/${transaction.id}',
                ),
                onDelete: (transaction) =>
                    _deleteTransaction(ref, transaction.id),
              ),
              loading: () => const _FeedLoading(),
              error: (error, _) => _FeedError(error: error),
            ),
          ],
        ),
      ),
    );
  }

  void _changeMonth(WidgetRef ref, DateTime month, int offset) {
    ref.read(selectedMonthProvider.notifier).state =
        DateTime(month.year, month.month + offset);
  }

  Future<void> _deleteTransaction(WidgetRef ref, String id) async {
    await ref.read(ledgerAppServiceProvider).deleteTransaction(id);
    ref.invalidate(monthTransactionsProvider);
    ref.invalidate(transactionListProvider);
    ref.invalidate(accountBalancesProvider);
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('流水加载失败：$error')),
      ),
    );
  }
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(
      child: SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
