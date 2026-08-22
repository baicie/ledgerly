import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/insight_period.dart';
import '../../l10n/l10n.dart';
import '../ai_providers.dart';
import '../quick_entry.dart';
import '../providers.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/feed_transaction_list.dart';
import '../widgets/ledgerly_layout.dart';
import '../widgets/ledgerly_summary_card.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final month = ref.watch(selectedMonthProvider);
    final transactions = ref.watch(monthTransactionsProvider);
    final summary = ref.watch(monthlyLedgerSummaryProvider);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final configured =
        ref.watch(aiSettingsControllerProvider).settings.isConfigured;
    return Scaffold(
      body: SafeArea(
        child: LedgerlyContent(
          slivers: [
            SliverToBoxAdapter(
              child: LedgerlyPageHeader(
                title: l10n.allTransactions,
                subtitle: l10n.standardLedger,
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
                    title: l10n.monthlyFeedStats,
                    balanceMinor: totals.balanceMinor,
                    incomeMinor: totals.incomeMinor,
                    expenseMinor: totals.expenseMinor,
                  ),
                ),
              ),
              loading: () => const _FeedLoading(),
              error: (error, _) => _FeedError(error: error),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    key: const Key('feed-monthly-insight-entry'),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(l10n.monthlyInsightEntryTitle),
                    subtitle: Text(l10n.monthlyInsightEntrySubtitle),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => context.go('/reports'),
                  ),
                ),
              ),
            ),
            transactions.when(
              skipLoadingOnReload: true,
              data: (items) => FeedTransactionList(
                transactions: items,
                todayInsight: isCurrentMonth ? const _TodayAiInsight() : null,
                orphanTodayInsight: isCurrentMonth && configured,
                onOpen: (transaction) =>
                    openQuickEntry(context, transaction: transaction),
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
    ref.read(selectedMonthProvider.notifier).state = DateTime(
      month.year,
      month.month + offset,
    );
  }

  Future<void> _deleteTransaction(WidgetRef ref, String id) async {
    await ref.read(ledgerAppServiceProvider).deleteTransaction(id);
    ref.invalidate(monthTransactionsProvider);
    ref.invalidate(transactionListProvider);
    ref.invalidate(accountBalancesProvider);
    ref.invalidate(categoryReportProvider);
    ref.invalidate(monthlyLedgerSummaryProvider);
    ref.invalidate(todayAiInsightProvider);
    ref.invalidate(selectedMonthAiInsightProvider);
  }
}

class _TodayAiInsight extends ConsumerWidget {
  const _TodayAiInsight();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayAiInsightProvider);
    return today.when(
      skipLoadingOnReload: true,
      data: (view) => AiInsightCard(
        view: view,
        embedded: true,
        onConfigure: () => context.go('/settings/ai'),
        onGenerate: view.canGenerate
            ? () => regenerateAiInsight(
                  ref,
                  InsightPeriod.daily(DateTime.now()),
                )
            : null,
      ),
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Text(l10nOf(context).insightLoadFailed('$error')),
      ),
    );
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
        child: Center(child: Text(l10nOf(context).feedLoadFailed('$error'))),
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
