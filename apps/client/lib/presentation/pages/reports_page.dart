import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../ai/insight_period.dart';
import '../../application/report_csv_formatter.dart';
import '../../application/reports_range.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/categories_sheet.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/range_picker_sheet.dart';
import '../widgets/report_insight_card.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = ref.watch(reportSummaryProvider);
    final trend = ref.watch(reportTrendProvider);
    final budget = ref.watch(reportBudgetProvider);
    final range = ref.watch(reportsRangeProvider);
    final rangeLabel = _rangeLabel(range);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.current.reportsTitle),
        actions: [
          if (range.isMonthAnchored) ...[
            IconButton(
              tooltip: L10n.current.reportsPrevMonth,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftAnchor(ref, -1),
            ),
          ],
          TextButton(
            onPressed: () => _openRangePicker(context, ref),
            child: Text(rangeLabel),
          ),
          if (range.isMonthAnchored) ...[
            IconButton(
              tooltip: L10n.current.reportsNextMonth,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shiftAnchor(ref, 1),
            ),
          ] else
            IconButton(
              tooltip: L10n.current.reportsRangeTitle,
              icon: const Icon(Icons.tune),
              onPressed: () => _openRangePicker(context, ref),
            ),
          IconButton(
            tooltip: L10n.current.reportsRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(reportSummaryProvider);
              ref.invalidate(reportTrendProvider);
              ref.invalidate(reportBudgetProvider);
            },
          ),
          PopupMenuButton<String>(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            tooltip: L10n.current.reportsExport,
            enabled: !_isExporting,
            onSelected: (value) => _onExportAction(context, value),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: const Icon(Icons.table_chart),
                  title: Text(L10n.current.reportsExportCsv),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: const Icon(Icons.share),
                  title: Text(L10n.current.reportsShare),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportSummaryProvider);
          ref.invalidate(reportTrendProvider);
          ref.invalidate(reportBudgetProvider);
          await Future.wait([
            ref.read(reportSummaryProvider.future),
            ref.read(reportTrendProvider.future),
            ref.read(reportBudgetProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroSummary(summary: summary),
            const SizedBox(height: 12),
            _PeriodChips(currentRange: range),
            const SizedBox(height: 16),
            ReportsInsightCard(
              period: InsightPeriod.monthOf(range.anchor),
              onConfigure: () => context.push('/settings/ai'),
              title: L10n.current.aiInsightCardTitle,
            ),
            const SizedBox(height: 24),
            _SectionTitle(text: L10n.current.reportsSummarySection),
            const SizedBox(height: 8),
            _SummaryCard(value: summary),
            const SizedBox(height: 24),
            _SectionTitle(text: L10n.current.reportsTrendSection),
            const SizedBox(height: 8),
            _TrendCard(
              value: trend,
              onJumpToMonth: (month) => _jumpToMonth(ref, month),
            ),
            const SizedBox(height: 24),
            if (range.kind == ReportsRangeKind.month) ...[
              _SectionTitle(text: L10n.current.reportsBudgetSection),
              const SizedBox(height: 8),
              _BudgetCard(value: budget, theme: theme),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onExportAction(
    BuildContext context,
    String action,
  ) async {
    final summary = ref.read(reportSummaryProvider);
    final trend = ref.read(reportTrendProvider);
    final range = ref.read(reportsRangeProvider);
    final label = _rangeLabel(range);

    final sData = summary.valueOrNull;
    final tData = trend.valueOrNull;
    if (sData == null || tData == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.current.reportsExportNoData)),
        );
      }
      return;
    }

    final formatter = ReportCsvFormatter(
      summary: sData,
      trend: tData,
      rangeLabel: label,
      currency: sData.baseCurrency,
    );

    if (action == 'csv') {
      setState(() => _isExporting = true);
      try {
        final csv = formatter.toCsv();
        final stamp = DateTime.now().toIso8601String().split('T').first;
        final fileName = 'report-$stamp.csv';
        await ref.read(userFilePortProvider).saveTextFile(
              fileName: fileName,
              contents: csv,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.current.reportsExportCsvDone),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${L10n.current.reportsExportCsvError}: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isExporting = false);
      }
    } else if (action == 'share') {
      final text = formatter.toShareText();
      await SharePlus.instance.share(
        ShareParams(text: text),
      );
    }
  }

  String _rangeLabel(ReportsRange range) {
    final anchor = range.anchor;
    switch (range.kind) {
      case ReportsRangeKind.month:
        return '${anchor.year.toString().padLeft(4, '0')}-${anchor.month.toString().padLeft(2, '0')}';
      case ReportsRangeKind.last3Months:
        return L10n.current.reportsRangeLast3;
      case ReportsRangeKind.last6Months:
        return L10n.current.reportsRangeLast6;
      case ReportsRangeKind.last7Days:
        return L10n.current.reportsRangeLast7;
      case ReportsRangeKind.last30Days:
        return L10n.current.reportsRangeLast30;
      case ReportsRangeKind.last90Days:
        return L10n.current.reportsRangeLast90;
      case ReportsRangeKind.year:
        return '${anchor.year}';
      case ReportsRangeKind.custom:
        final s = range.customStart;
        final e = range.customEnd;
        if (s == null || e == null) return L10n.current.reportsRangeCustom;
        final sFmt =
            '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
        final eFmt =
            '${e.year}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}';
        return '$sFmt → $eFmt';
    }
  }

  Future<void> _openRangePicker(BuildContext context, WidgetRef ref) async {
    final current = ref.read(reportsRangeProvider);
    final picked = await RangePickerSheet.show(context, current: current);
    if (picked == null) return;
    ref.read(reportsRangeProvider.notifier).state = picked;
    unawaitedPersist(ref, picked);
    ref.invalidate(reportSummaryProvider);
    ref.invalidate(reportTrendProvider);
    ref.invalidate(reportBudgetProvider);
  }

  void _shiftAnchor(WidgetRef ref, int delta) {
    final current = ref.read(reportsRangeProvider);
    if (delta == 0) {
      final now = DateTime.now();
      ref.read(reportsRangeProvider.notifier).state =
          current.withAnchor(DateTime(now.year, now.month));
    } else {
      final next = DateTime(
        current.anchor.year,
        current.anchor.month + delta,
      );
      final now = DateTime.now();
      if (delta > 0 && next.isAfter(DateTime(now.year, now.month))) return;
      ref.read(reportsRangeProvider.notifier).state = current.withAnchor(next);
    }
    unawaitedPersist(ref, ref.read(reportsRangeProvider));
    ref.invalidate(reportSummaryProvider);
    ref.invalidate(reportTrendProvider);
    ref.invalidate(reportBudgetProvider);
  }

  /// Switch the range to a single-month view for the given [month]. Used
  /// when the user taps a trend point and wants to drill into that month.
  void _jumpToMonth(WidgetRef ref, DateTime month) {
    ref.read(reportsRangeProvider.notifier).state =
        ReportsRange.month(month);
    unawaitedPersist(ref, ref.read(reportsRangeProvider));
    ref.invalidate(reportSummaryProvider);
    ref.invalidate(reportTrendProvider);
    ref.invalidate(reportBudgetProvider);
  }
}

void unawaitedPersist(WidgetRef ref, ReportsRange range) {
  final store = ref.read(reportsRangeStoreProvider);
  // Fire-and-forget: persistence failures shouldn't block the UI.
  // ignore: unawaited_futures
  store.write(range);
}

class _HeroSummary extends ConsumerWidget {
  const _HeroSummary({required this.summary});
  final AsyncValue<ReportSummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetAsync = ref.watch(reportBudgetProvider);

    final isLoading = summary.isLoading && !summary.hasValue;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isLoading
          ? const _HeroSummarySkeleton(key: ValueKey('hero-skel'))
          : _HeroSummaryContent(
              key: const ValueKey('hero-data'),
              summary: summary,
              budgetAsync: budgetAsync,
            ),
    );
  }
}

class _HeroSummaryContent extends StatelessWidget {
  const _HeroSummaryContent({
    super.key,
    required this.summary,
    required this.budgetAsync,
  });
  final AsyncValue<ReportSummary> summary;
  final AsyncValue<List<ReportBudgetItem>> budgetAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budgetItems = budgetAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <ReportBudgetItem>[],
    );

    final s = summary.maybeWhen(
      data: (v) => v,
      orElse: () => null,
    );

    final incomeColor = theme.colorScheme.primary;
    final expenseColor = theme.colorScheme.error;
    final netColor = s != null
        ? (s.netMinor >= BigInt.zero
            ? Colors.green.shade700
            : theme.colorScheme.error)
        : theme.colorScheme.outline;

    String incomeText = '—';
    String expenseText = '—';
    String netText = '—';
    String budgetText = L10n.current.reportsHeroBudgetUnset;
    Color budgetColor = theme.colorScheme.outline;
    if (s != null) {
      incomeText = formatMinor(s.incomeMinor);
      expenseText = formatMinor(s.expenseMinor);
      final signed = s.netMinor;
      final sign = signed >= BigInt.zero ? '+' : '−';
      netText = '$sign${formatMinor(signed.abs())}';
    }
    if (budgetItems.isNotEmpty) {
      var totalBudget = BigInt.zero;
      var totalActual = BigInt.zero;
      for (final b in budgetItems) {
        totalBudget += b.budgetMinor;
        totalActual += b.actualMinor;
      }
      final left = totalBudget - totalActual;
      final pct = totalBudget == BigInt.zero
          ? 0.0
          : (left.toDouble() / totalBudget.toDouble()).clamp(-1.0, 1.0);
      final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';
      budgetText =
          left >= BigInt.zero ? pctLabel : '−${(-pct * 100).toStringAsFixed(0)}%';
      budgetColor = pct >= 0
          ? (pct >= 0.3 ? Colors.green.shade700 : Colors.orange.shade700)
          : theme.colorScheme.error;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: _HeroStat(
                label: L10n.current.reportsHeroIncome,
                value: incomeText,
                color: incomeColor,
                icon: Icons.trending_up,
              ),
            ),
            _HeroDivider(color: theme.colorScheme.outlineVariant),
            Expanded(
              child: _HeroStat(
                label: L10n.current.reportsHeroExpense,
                value: expenseText,
                color: expenseColor,
                icon: Icons.trending_down,
              ),
            ),
            _HeroDivider(color: theme.colorScheme.outlineVariant),
            Expanded(
              child: _HeroStat(
                label: L10n.current.reportsHeroNet,
                value: netText,
                color: netColor,
                icon: Icons.swap_vert,
              ),
            ),
            _HeroDivider(color: theme.colorScheme.outlineVariant),
            Expanded(
              child: _HeroStat(
                label: L10n.current.reportsHeroBudgetLeft,
                value: budgetText,
                color: budgetColor,
                icon: Icons.savings_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroSummarySkeleton extends StatelessWidget {
  const _HeroSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) _HeroDivider(color: theme.colorScheme.outlineVariant),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: base,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 56,
                      height: 18,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 36,
                      height: 10,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  const _HeroDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: color.withValues(alpha: 0.3),
    );
  }
}

class _PeriodChips extends ConsumerWidget {
  const _PeriodChips({required this.currentRange});
  final ReportsRange currentRange;

  bool _matches(ReportsRangeKind kind) {
    return currentRange.kind == kind;
  }

  void _setRange(WidgetRef ref, ReportsRange range) {
    ref.read(reportsRangeProvider.notifier).state = range;
    unawaitedPersist(ref, range);
    ref.invalidate(reportSummaryProvider);
    ref.invalidate(reportTrendProvider);
    ref.invalidate(reportBudgetProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = <_ChipEntry>[
      _ChipEntry(
        kind: ReportsRangeKind.month,
        label: L10n.current.reportsRangeMonth,
        builder: () => ReportsRange.month(currentRange.anchor),
      ),
      _ChipEntry(
        kind: ReportsRangeKind.last3Months,
        label: L10n.current.reportsRangeLast3,
        builder: () => ReportsRange.last3Months(currentRange.anchor),
      ),
      _ChipEntry(
        kind: ReportsRangeKind.last6Months,
        label: L10n.current.reportsRangeLast6,
        builder: () => ReportsRange.last6Months(currentRange.anchor),
      ),
      _ChipEntry(
        kind: ReportsRangeKind.year,
        label: L10n.current.reportsRangeYear,
        builder: () => ReportsRange.year(currentRange.anchor),
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          ChoiceChip(
            label: Text(entry.label),
            selected: _matches(entry.kind),
            onSelected: (_) => _setRange(ref, entry.builder()),
            labelStyle: theme.textTheme.labelMedium,
          ),
      ],
    );
  }
}

class _ChipEntry {
  const _ChipEntry({
    required this.kind,
    required this.label,
    required this.builder,
  });
  final ReportsRangeKind kind;
  final String label;
  final ReportsRange Function() builder;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _SummaryCard extends ConsumerStatefulWidget {
  const _SummaryCard({required this.value});
  final AsyncValue<ReportSummary> value;

  @override
  ConsumerState<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<_SummaryCard> {
  Timer? _ticker;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void doRefresh() {
      ref.invalidate(reportSummaryProvider);
    }

    // Capture load time when data first arrives.
    widget.value.whenData((_) {
      _loadedAt ??= DateTime.now();
    });

    return widget.value.when(
      loading: () => const _LoadingCard(height: 220),
      error: (err, _) => _ErrorCard(
        message: err.toString(),
        onRetry: doRefresh,
      ),
      data: (summary) {
        final currency = summary.baseCurrency;
        final visible = summary.categories.take(5).toList();
        final overflow = summary.categories.length > 5
            ? summary.categories.length - 5
            : 0;
        final slices = [
          for (final c in summary.categories)
            CategorySlice(label: c.name, amountMinor: c.amountMinor),
        ];
        final cardTheme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cardTheme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            size: 14,
                            color: cardTheme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${L10n.current.reportsBaseCurrency} · $currency',
                            style: cardTheme.textTheme.labelSmall?.copyWith(
                              color: cardTheme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 12),
                _MetricRow(
                  label: L10n.current.reportsIncome,
                  amount: summary.incomeMinor,
                  currency: currency,
                  color: Colors.green.shade700,
                ),
                const SizedBox(height: 12),
                _MetricRow(
                  label: L10n.current.reportsExpense,
                  amount: summary.expenseMinor,
                  currency: currency,
                  color: Colors.red.shade700,
                ),
                const Divider(height: 24),
                _MetricRow(
                  label: L10n.current.reportsNet,
                  amount: summary.netMinor,
                  currency: currency,
                  color: summary.netMinor >= BigInt.zero
                      ? Colors.blue.shade700
                      : Colors.orange.shade800,
                  emphasized: true,
                ),
                if (summary.categories.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CategoryPieChart(slices: slices),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final c in visible) _CategoryRow(item: c),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (overflow > 0) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => CategoriesSheet.show(
                          context,
                          categories: summary.categories,
                        ),
                        icon: const Icon(Icons.unfold_more),
                        label: Text(L10n.current.reportsAllCategories(
                            overflow)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_loadedAt != null)
                    _UpdatedTimestamp(loadedAt: _loadedAt!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UpdatedTimestamp extends StatelessWidget {
  const _UpdatedTimestamp({required this.loadedAt});

  final DateTime loadedAt;

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return L10n.current.reportsUpdatedJustNow;
    if (d.inMinutes < 60) {
      return L10n.current.reportsUpdatedAgo('${d.inMinutes}m');
    }
    if (d.inHours < 24) {
      return L10n.current.reportsUpdatedAgo('${d.inHours}h');
    }
    return L10n.current.reportsUpdatedAgo('${d.inDays}d');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = DateTime.now().difference(loadedAt);
    return Text(
      _formatDuration(diff),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.item});
  final ReportCategory item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hash = item.name.codeUnits.fold<int>(0, (a, b) => (a + b) & 0xffffff);
    final hue = (hash % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.55, 0.55).toColor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            '${formatMinor(item.amountMinor)} ${item.currency}',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    required this.value,
    required this.onJumpToMonth,
  });
  final AsyncValue<List<ReportTrendPoint>> value;
  final ValueChanged<DateTime> onJumpToMonth;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
      loading: () => const _LoadingCard(height: 220),
      error: (err, _) {
        return Builder(
          builder: (ctx) => _ErrorCard(
            message: err.toString(),
            onRetry: () {
              // Refresh only the trend provider.
              // ProviderScope isn't accessible from here, but we can
              // piggyback on the parent's build via setState since the
              // consumer's parent owns ref.
              if (mounted) setState(() {});
            },
          ),
        );
      },
      data: (points) {
        if (points.isEmpty) {
          return const _EmptyCard(
            text: 'No trend data',
            icon: Icons.show_chart,
          );
        }
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 180,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, 180);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _handleTap(details.localPosition, size, points),
                        onLongPressStart: (details) =>
                            _handleTap(details.localPosition, size, points),
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: size,
                              painter: _TrendPainter(
                                points: points,
                                incomeColor: Colors.green.shade600,
                                expenseColor: Colors.red.shade600,
                                axisColor: theme.dividerColor,
                                labelStyle: theme.textTheme.labelSmall ??
                                    const TextStyle(),
                                selectedIndex: _selectedIndex,
                                netColor: theme.colorScheme.primary,
                              ),
                            ),
                            if (_selectedIndex != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _TrendTooltip(point: points[_selectedIndex!]),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    _Legend(
                        color: Colors.green.shade600,
                        label: L10n.current.reportsIncome),
                    _Legend(
                        color: Colors.red.shade600,
                        label: L10n.current.reportsExpense),
                    _Legend(
                        color: Theme.of(context).colorScheme.primary,
                        label: L10n.current.reportsNet),
                  ],
                ),
                if (_selectedIndex != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Builder(
                      builder: (ctx) => TextButton.icon(
                        onPressed: () => _jumpToSelected(),
                        icon: const Icon(Icons.event),
                        label: Text(L10n.current.reportsTrendJumpToMonth),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleTap(
    Offset position,
    Size size,
    List<ReportTrendPoint> points,
  ) {
    const padLeft = 32.0;
    const padRight = 8.0;
    final chartWidth = size.width - padLeft - padRight;
    if (points.isEmpty) return;

    int bestIndex = 0;
    double bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final step = points.length == 1
          ? 0.0
          : chartWidth / (points.length - 1);
      final x = padLeft + step * i;
      final d = (position.dx - x).abs();
      if (d < bestDistance) {
        bestDistance = d;
        bestIndex = i;
      }
    }
    if (bestDistance > 32) {
      setState(() => _selectedIndex = null);
      return;
    }
    setState(() {
      _selectedIndex = _selectedIndex == bestIndex ? null : bestIndex;
    });
  }

  void _jumpToSelected() {
    if (_selectedIndex == null) return;
    final points = widget.value.valueOrNull;
    if (points == null) return;
    final monthStr = points[_selectedIndex!].month; // YYYY-MM
    final parts = monthStr.split('-');
    if (parts.length < 2) return;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return;
    widget.onJumpToMonth(DateTime(year, month));
    setState(() => _selectedIndex = null);
  }
}

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({required this.point});
  final ReportTrendPoint point;

  String _money(BigInt v) => formatMinor(v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            point.month,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onInverseSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${L10n.current.reportsIncome} ${_money(point.incomeMinor)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.green.shade200,
            ),
          ),
          Text(
            '${L10n.current.reportsExpense} ${_money(point.expenseMinor)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.red.shade200,
            ),
          ),
          Text(
            '${L10n.current.reportsNet} ${_money(point.netMinor)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: point.netMinor >= BigInt.zero
                  ? Colors.lightGreenAccent.shade100
                  : Colors.orangeAccent.shade100,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.value, required this.theme});
  final AsyncValue<List<ReportBudgetItem>> value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void doRefresh() {
      ref.invalidate(reportBudgetProvider);
    }

    return value.when(
      loading: () => const _LoadingCard(height: 120),
      error: (err, _) => _ErrorCard(
        message: err.toString(),
        onRetry: doRefresh,
      ),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyCard(
            text: L10n.current.reportsBudgetEmptyTitle,
            icon: Icons.savings_outlined,
            actionLabel: L10n.current.reportsBudgetEmptyAction,
            onAction: () => context.push('/settings/budgets'),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _BudgetRow(item: item),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.item});
  final ReportBudgetItem item;

  @override
  Widget build(BuildContext context) {
    final ratio = item.ratio.clamp(0.0, 2.0);
    Color color;
    switch (item.status) {
      case 'over':
        color = Colors.red.shade700;
        break;
      case 'ok':
        color = Colors.orange.shade700;
        break;
      default:
        color = Colors.green.shade700;
    }
    final percentLabel = '${(ratio * 100).toStringAsFixed(0)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            Text(
              '${formatMinor(item.actualMinor)} / ${formatMinor(item.budgetMinor)} ${item.currency}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio > 1 ? 1 : ratio,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            color: color,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          percentLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    this.emphasized = false,
  });

  final String label;
  final BigInt amount;
  final String currency;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: color)
        : Theme.of(context).textTheme.bodyLarge?.copyWith(color: color);
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            '${formatMinor(amount)} $currency',
            key: ValueKey(amount.toString() + currency),
            style: style,
          ),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainerHigh;
    return Card(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title placeholder
              Container(
                width: 120,
                height: 16,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              // Big numbers (3 bars)
              Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      height: 36,
                      decoration: BoxDecoration(
                        color: i.isEven ? base : highlight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Bottom bars (category list placeholder)
              Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      height: 12,
                      decoration: BoxDecoration(
                        color: highlight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(
                  onPressed: onRetry,
                  child: Text(L10n.current.commonRetry),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.text,
    this.icon,
    this.actionLabel,
    this.onAction,
  });
  final String text;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.incomeColor,
    required this.expenseColor,
    required this.axisColor,
    required this.labelStyle,
    required this.netColor,
    this.selectedIndex,
  });

  final List<ReportTrendPoint> points;
  final Color incomeColor;
  final Color expenseColor;
  final Color axisColor;
  final TextStyle labelStyle;
  final Color netColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const padBottom = 24.0;
    const padLeft = 36.0;
    const padRight = 8.0;
    const padTop = 8.0;

    final chartWidth = size.width - padLeft - padRight;
    final chartHeight = size.height - padTop - padBottom;

    // Compute absolute extremes across income, expense, and net (signed).
    BigInt absMax = BigInt.zero;
    BigInt minNet = BigInt.zero;
    BigInt maxNet = BigInt.zero;
    for (final p in points) {
      if (p.incomeMinor.abs() > absMax) absMax = p.incomeMinor.abs();
      if (p.expenseMinor.abs() > absMax) absMax = p.expenseMinor.abs();
      if (p.netMinor.abs() > absMax) absMax = p.netMinor.abs();
      if (p.netMinor < minNet) minNet = p.netMinor;
      if (p.netMinor > maxNet) maxNet = p.netMinor;
    }
    final scale = absMax == BigInt.zero ? 0.0 : chartHeight / 2 / absMax.toDouble();
    // Zero baseline for signed net (income & expense always >= 0; pin to top of chart space).
    final zeroBaselineY = padTop + chartHeight / 2;

    // Axis
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(padLeft, padTop + chartHeight),
      Offset(padLeft + chartWidth, padTop + chartHeight),
      axisPaint,
    );
    // Zero line for net (dashed)
    if (minNet < BigInt.zero || maxNet > BigInt.zero) {
      final dashPaint = Paint()
        ..color = axisColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.0;
      const dashWidth = 6.0;
      const dashGap = 4.0;
      double dx = padLeft;
      while (dx < padLeft + chartWidth) {
        final end = (dx + dashWidth).clamp(padLeft, padLeft + chartWidth);
        canvas.drawLine(
          Offset(dx, zeroBaselineY),
          Offset(end, zeroBaselineY),
          dashPaint,
        );
        dx = end + dashGap;
      }
    }

    // Y-axis tick marks and labels.
    if (absMax > BigInt.zero) {
      // Top label: +absMax
      _drawYLabel(
        canvas,
        padTop,
        absMax,
        padLeft,
        labelStyle,
      );
      // Bottom label: 0 (income/expense scale; net shows negative below baseline).
      _drawYLabel(
        canvas,
        padTop + chartHeight,
        BigInt.zero,
        padLeft,
        labelStyle,
      );
      // Tick marks.
      final tickPaint = Paint()
        ..color = axisColor.withValues(alpha: 0.4)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(padLeft, padTop),
        Offset(padLeft + chartWidth, padTop),
        tickPaint,
      );
      canvas.drawLine(
        Offset(padLeft, padTop + chartHeight),
        Offset(padLeft + chartWidth, padTop + chartHeight),
        tickPaint,
      );
    }

    final step = points.length == 1
        ? 0.0
        : chartWidth / (points.length - 1);

    final incomePath = Path();
    final expensePath = Path();
    final netPath = Path();
    final dotPositions = <Offset>[];
    final netPositions = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = padLeft + step * i;
      // Income & expense share the top-anchored scale (they're always >= 0).
      final topScale = absMax == BigInt.zero
          ? 0.0
          : chartHeight / absMax.toDouble();
      final incomeY = padTop + chartHeight - points[i].incomeMinor.toDouble() * topScale;
      final expenseY = padTop + chartHeight - points[i].expenseMinor.toDouble() * topScale;
      // Net uses signed scale around the middle line.
      final netY = zeroBaselineY - points[i].netMinor.toDouble() * scale;
      if (i == 0) {
        incomePath.moveTo(x, incomeY);
        expensePath.moveTo(x, expenseY);
        netPath.moveTo(x, netY);
      } else {
        incomePath.lineTo(x, incomeY);
        expensePath.lineTo(x, expenseY);
        netPath.lineTo(x, netY);
      }

      // X-axis label
      final tp = TextPainter(
        text: TextSpan(text: points[i].month.substring(5), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, padTop + chartHeight + 4),
      );

      dotPositions.add(Offset(x, incomeY));
      dotPositions.add(Offset(x, expenseY));
      netPositions.add(Offset(x, netY));
    }

    final incomePaint = Paint()
      ..color = incomeColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final expensePaint = Paint()
      ..color = expenseColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(incomePath, incomePaint);
    canvas.drawPath(expensePath, expensePaint);

    // Net line: dashed, thin
    final netPathMetrics = netPath.computeMetrics().toList();
    final netPaint = Paint()
      ..color = netColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final m in netPathMetrics) {
      const dashLen = 5.0;
      const gapLen = 3.0;
      double dist = 0.0;
      while (dist < m.length) {
        final next = (dist + dashLen).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(dist, next), netPaint);
        dist = next + gapLen;
      }
    }

    // Highlight selected dot if active
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final selectedX = padLeft + step * selectedIndex!;
      // Vertical guide line
      final guidePaint = Paint()
        ..color = axisColor.withValues(alpha: 0.4)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(selectedX, padTop),
        Offset(selectedX, padTop + chartHeight),
        guidePaint,
      );
      // Highlight the two dots
      final hiPaint = Paint()..color = Colors.amber.shade700;
      canvas.drawCircle(dotPositions[selectedIndex! * 2], 6, hiPaint);
      canvas.drawCircle(dotPositions[selectedIndex! * 2 + 1], 6, hiPaint);
      canvas.drawCircle(netPositions[selectedIndex!], 6, hiPaint);
    } else {
      // Plain dots
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(dotPositions[i * 2], 3,
            Paint()..color = incomeColor);
        canvas.drawCircle(dotPositions[i * 2 + 1], 3,
            Paint()..color = expenseColor);
      }
      for (final p in netPositions) {
        canvas.drawCircle(p, 2.5, Paint()..color = netColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) {
    if (old.points.length != points.length) return true;
    if (old.selectedIndex != selectedIndex) return true;
    if (old.netColor != netColor) return true;
    for (var i = 0; i < points.length; i++) {
      if (old.points[i].incomeMinor != points[i].incomeMinor) return true;
      if (old.points[i].expenseMinor != points[i].expenseMinor) return true;
      if (old.points[i].netMinor != points[i].netMinor) return true;
    }
    return false;
  }

  void _drawYLabel(
    Canvas canvas,
    double y,
    BigInt value,
    double padLeft,
    TextStyle labelStyle,
  ) {
    final labelText = formatMinor(value);
    final tp = TextPainter(
      text: TextSpan(text: labelText, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(padLeft - tp.width - 4, y - tp.height / 2));
  }
}
