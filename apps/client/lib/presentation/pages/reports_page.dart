import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/insight_period.dart';
import '../../data/ledger_repository.dart';
import '../../l10n/l10n.dart';
import '../ai_providers.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';
import '../widgets/ledgerly_summary_card.dart';
import '../widgets/ledgerly_trend_chart.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  Map<String, dynamic>? _remote;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  Future<void> _loadRemote() async {
    if (ref.read(apiEndpointProvider) == null) return;
    try {
      final api = ref.read(syncApiProvider);
      final bookId = ref.read(authRepositoryProvider).currentSession?.bookId;
      if (bookId == null) return;
      final month = ref.read(selectedMonthProvider);
      final range = monthUtcRange(month);
      final summary = await api.reportSummary(
        bookId: bookId,
        from: range.start.toIso8601String(),
        to: range.end.toIso8601String(),
      );
      if (mounted) {
        setState(() {
          _remote = summary;
          _remoteError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _remoteError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(categoryReportProvider);
    final totals = ref.watch(monthlyLedgerSummaryProvider);
    final transactions = ref.watch(monthTransactionsProvider);
    final month = ref.watch(selectedMonthProvider);
    final isLocal = ref.watch(apiEndpointProvider) == null;
    final l10n = l10nOf(context);

    return Scaffold(
      body: SafeArea(
        child: LedgerlyContent(
          slivers: [
            SliverToBoxAdapter(
              child: LedgerlyPageHeader(
                title: l10n.reportsTitle,
                subtitle:
                    '${isLocal ? l10n.localShort : l10n.syncedShort} · ${month.year}-${month.month.toString().padLeft(2, '0')}',
                actions: [
                  if (!isLocal)
                    IconButton(
                      tooltip: l10n.refreshRemoteSummary,
                      icon: const Icon(Icons.sync_rounded),
                      onPressed: _loadRemote,
                    ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: LedgerlyMonthPicker(
                month: month,
                onPrevious: () => _changeMonth(month, -1),
                onNext: () => _changeMonth(month, 1),
              ),
            ),
            totals.when(
              data: (summary) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                sliver: SliverToBoxAdapter(
                  child: LedgerlySummaryCard(
                    title: l10n.monthlyFlowStats,
                    balanceMinor: summary.balanceMinor,
                    incomeMinor: summary.incomeMinor,
                    expenseMinor: summary.expenseMinor,
                  ),
                ),
              ),
              loading: () => const _ReportPlaceholder(height: 220),
              error: (error, _) => _ReportError(error: error),
            ),
            ..._reportInsightSlivers(context, ref, month),
            transactions.when(
              data: (items) {
                final rows = _aggregateIncome(items);
                final total = rows.fold<BigInt>(
                  BigInt.zero,
                  (value, row) => value + row.amount,
                );
                return _RankingSection(
                  title: l10n.incomeSources,
                  rows: rows,
                  total: total,
                  emptyMessage: l10n.noIncomeThisMonth,
                  income: true,
                );
              },
              loading: () => const _ReportPlaceholder(height: 136),
              error: (error, _) => _ReportError(error: error),
            ),
            report.when(
              data: (rows) {
                final total = rows.fold<BigInt>(
                  BigInt.zero,
                  (value, row) => value + row.amount,
                );
                return _RankingSection(
                  title: l10n.expenseBreakdown,
                  rows: rows,
                  total: total,
                  emptyMessage: l10n.noExpenseThisMonth,
                );
              },
              loading: () => const _ReportPlaceholder(height: 136),
              error: (error, _) => _ReportError(error: error),
            ),
            transactions.when(
              data: (items) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                sliver: SliverToBoxAdapter(
                  child: LedgerlySection(
                    title: l10n.monthlyTrend,
                    child: LedgerlyTrendChart(
                      month: month,
                      transactions: items,
                    ),
                  ),
                ),
              ),
              loading: () => const _ReportPlaceholder(height: 240),
              error: (error, _) => _ReportError(error: error),
            ),
            if (!isLocal && (_remote != null || _remoteError != null))
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                sliver: SliverToBoxAdapter(
                  child: _RemoteSummary(data: _remote, error: _remoteError),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _changeMonth(DateTime month, int offset) {
    ref.read(selectedMonthProvider.notifier).state = DateTime(
      month.year,
      month.month + offset,
    );
    _loadRemote();
  }

  List<Widget> _reportInsightSlivers(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
  ) {
    final monthly = ref.watch(selectedMonthAiInsightProvider);
    return [
      monthly.when(
        skipLoadingOnReload: true,
        data: (view) => SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: AiInsightCard(
              view: view,
              onConfigure: () => context.go('/settings/ai'),
              onGenerate: view.canGenerate
                  ? () => regenerateAiInsight(ref, InsightPeriod.monthOf(month))
                  : null,
            ),
          ),
        ),
        loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
        error: (error, _) => _ReportError(error: error),
      ),
    ];
  }

  List<CategoryAmount> _aggregateIncome(List<TransactionSummary> transactions) {
    final amounts = <String, BigInt>{};
    final counts = <String, int>{};
    for (final transaction in transactions) {
      if (transaction.kind != TransactionSummaryKind.income) continue;
      final category = transaction.categoryName ?? 'Other';
      amounts.update(
        category,
        (amount) => amount + transaction.amountMinor,
        ifAbsent: () => transaction.amountMinor,
      );
      counts.update(category, (count) => count + 1, ifAbsent: () => 1);
    }
    final rows = amounts.entries
        .map(
          (entry) => CategoryAmount(
            name: entry.key,
            amount: entry.value,
            transactionCount: counts[entry.key] ?? 0,
          ),
        )
        .toList();
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }
}

class _RankingList extends StatelessWidget {
  const _RankingList({
    required this.rows,
    required this.total,
    required this.emptyMessage,
    this.income = false,
  });

  final List<CategoryAmount> rows;
  final BigInt total;
  final String emptyMessage;
  final bool income;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < rows.length; index++)
          LedgerlyProgressRow(
            rank: index + 1,
            name: localizedLedgerName(l10nOf(context), rows[index].name),
            subtitle: l10nOf(context)
                .transactionCountLabel(rows[index].transactionCount),
            amount: rows[index].amount,
            fraction: total == BigInt.zero
                ? 0
                : rows[index].amount.toDouble() / total.toDouble(),
            icon: ledgerIconFor(rows[index].name),
            color: income
                ? LedgerlyColors.income
                : ledgerColorFor(rows[index].name),
          ),
      ],
    );
  }
}

class _RankingSection extends StatelessWidget {
  const _RankingSection({
    required this.title,
    required this.rows,
    required this.total,
    required this.emptyMessage,
    this.income = false,
  });

  final String title;
  final List<CategoryAmount> rows;
  final BigInt total;
  final String emptyMessage;
  final bool income;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      sliver: SliverToBoxAdapter(
        child: LedgerlySection(
          title: title,
          trailing: Text(
            l10nOf(context).rankingTrailing(
              rows.fold<int>(
                0,
                (count, row) => count + row.transactionCount,
              ),
              formatDisplayMinor(total),
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          child: _RankingList(
            rows: rows,
            total: total,
            emptyMessage: emptyMessage,
            income: income,
          ),
        ),
      ),
    );
  }
}

class _RemoteSummary extends StatelessWidget {
  const _RemoteSummary({required this.data, required this.error});

  final Map<String, dynamic>? data;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return LedgerlySection(
      title: l10nOf(context).cloudCheck,
      child: error != null
          ? Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          : Text(
              l10nOf(context).remoteNet(
                '${data?['netMinor'] ?? '--'}',
                '${data?['baseCurrency'] ?? 'CNY'}',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
    );
  }
}

class _ReportPlaceholder extends StatelessWidget {
  const _ReportPlaceholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      sliver: SliverToBoxAdapter(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: LedgerlyColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: LedgerlyColors.divider),
          ),
        ),
      ),
    );
  }
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l10nOf(context).reportsLoadFailed('$error')),
      ),
    );
  }
}
