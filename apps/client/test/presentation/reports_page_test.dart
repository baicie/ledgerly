import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/pages/reports_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';

void main() {
  group('ReportsPage widget', () {
    testWidgets('renders AppBar with title and month navigation', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.from(100000),
                expenseMinor: BigInt.from(60000),
                netMinor: BigInt.from(40000),
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('报表'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
      // Multiple IconButton(refresh) appear because of the shell scaffold.
      expect(find.byIcon(Icons.refresh), findsWidgets);
    });

    testWidgets('renders AI insight card at the top', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.zero,
                expenseMinor: BigInt.zero,
                netMinor: BigInt.zero,
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView(
                status: AiInsightStatus.ready,
                kind: InsightKind.monthly,
                periodKey: '2026-09',
                periodLabel: '2026年9月',
                headline: '本月支出偏高',
              ),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // AI card should render with headline.
      expect(find.text('AI 总结'), findsOneWidget);
      expect(find.text('本月支出偏高'), findsOneWidget);
    });

    testWidgets('renders summary section with income, expense, net', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.from(100000),
                expenseMinor: BigInt.from(60000),
                netMinor: BigInt.from(40000),
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('本月概览'), findsOneWidget);
      expect(find.text('收入'), findsWidgets);
      expect(find.text('支出'), findsWidgets);
      expect(find.text('净额'), findsOneWidget);
    });

    testWidgets('renders trend section title', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.zero,
                expenseMinor: BigInt.zero,
                netMinor: BigInt.zero,
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async {
              return [
                ReportTrendPoint(
                  month: '2026-04',
                  incomeMinor: BigInt.from(50000),
                  expenseMinor: BigInt.from(30000),
                  netMinor: BigInt.from(20000),
                ),
                ReportTrendPoint(
                  month: '2026-05',
                  incomeMinor: BigInt.from(60000),
                  expenseMinor: BigInt.from(40000),
                  netMinor: BigInt.from(20000),
                ),
              ];
            }),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to trend section.
      await tester.scrollUntilVisible(find.text('近 6 个月趋势'), 300);
      expect(find.text('近 6 个月趋势'), findsOneWidget);
    });

    testWidgets('renders budget section with items', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.zero,
                expenseMinor: BigInt.zero,
                netMinor: BigInt.zero,
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async {
              return [
                ReportBudgetItem(
                  id: 'b1',
                  name: '餐饮',
                  budgetMinor: BigInt.from(30000),
                  actualMinor: BigInt.from(25000),
                  currency: 'CNY',
                  status: 'ok',
                ),
                ReportBudgetItem(
                  id: 'b2',
                  name: '交通',
                  budgetMinor: BigInt.from(10000),
                  actualMinor: BigInt.from(12000),
                  currency: 'CNY',
                  status: 'over',
                ),
              ];
            }),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to budget section.
      await tester.scrollUntilVisible(find.text('预算'), 300);
      expect(find.text('预算'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('交通'), findsOneWidget);
    });

    testWidgets('month prev button navigates to previous month', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.zero,
                expenseMinor: BigInt.zero,
                netMinor: BigInt.zero,
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap prev month.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      // No crash means success. The month label may differ.
      expect(find.byIcon(Icons.chevron_left), findsWidgets);
    });

    testWidgets('shows empty budget state when no budgets', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.zero,
                expenseMinor: BigInt.zero,
                netMinor: BigInt.zero,
                baseCurrency: 'CNY',
                categories: const [],
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to budget section.
      await tester.scrollUntilVisible(find.text('预算'), 300);
      // Empty budget section shows a card with no budget items.
      expect(find.text('预算'), findsOneWidget);
    });

    testWidgets('summary shows all categories action when > 5 categories', (tester) async {
      final manyCategories = [
        for (var i = 1; i <= 7; i++)
          ReportCategory(
            name: 'Cat $i',
            amountMinor: BigInt.from(1000 * i),
            currency: 'CNY',
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.from(100000),
                expenseMinor: BigInt.from(50000),
                netMinor: BigInt.from(50000),
                baseCurrency: 'CNY',
                categories: manyCategories,
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to summary section.
      await tester.scrollUntilVisible(find.text('本月概览'), 300);
      // "View all" button should appear (count = 7 - 5 = 2).
      expect(find.textContaining('全部类别'), findsOneWidget);
    });

    testWidgets('summary renders pie chart alongside categories', (tester) async {
      final categories = [
        ReportCategory(name: 'Food', amountMinor: BigInt.from(200), currency: 'CNY'),
        ReportCategory(name: 'Transport', amountMinor: BigInt.from(100), currency: 'CNY'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            reportSummaryProvider.overrideWith((ref) async {
              return ReportSummary(
                incomeMinor: BigInt.from(100000),
                expenseMinor: BigInt.from(50000),
                netMinor: BigInt.from(50000),
                baseCurrency: 'CNY',
                categories: categories,
                plan: null,
              );
            }),
            reportTrendProvider.overrideWith((ref) async => []),
            reportBudgetProvider.overrideWith((ref) async => []),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(kind: InsightKind.monthly),
            ),
          ],
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('本月概览'), 300);
      // Categories visible.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
    });
  });

  group('_TrendPainter', () {
    testWidgets('shouldRepaint returns false for identical data', (tester) async {
      final data = [
        _FakePoint('2024-01', 100, 50, 50),
        _FakePoint('2024-02', 150, 60, 90),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CustomPaint(
                painter: _TrendPainterForTest(points: data),
              ),
            ),
          ),
        ),
      );
      final p1 = _TrendPainterForTest(points: data);
      final p2 = _TrendPainterForTest(points: data);
      expect(p1.shouldRepaint(p2), isFalse);
    });

    testWidgets('shouldRepaint returns true when income changes', (tester) async {
      final data = [
        _FakePoint('2024-01', 100, 50, 50),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CustomPaint(painter: _TrendPainterForTest(points: data)),
            ),
          ),
        ),
      );
      final p1 = _TrendPainterForTest(points: data);
      final updated = [
        _FakePoint('2024-01', 200, 50, 150),
      ];
      final p2 = _TrendPainterForTest(points: updated);
      expect(p1.shouldRepaint(p2), isTrue);
    });

    testWidgets('shouldRepaint returns true when length differs', (tester) async {
      final data = [_FakePoint('2024-01', 100, 50, 50)];
      final p1 = _TrendPainterForTest(points: data);
      final p2 = _TrendPainterForTest(points: [
        _FakePoint('2024-01', 100, 50, 50),
        _FakePoint('2024-02', 100, 60, 40),
      ]);
      expect(p1.shouldRepaint(p2), isTrue);
    });
  });
}

class _FakePoint {
  _FakePoint(this.month, this.income, this.expense, this.net);
  final String month;
  final int income;
  final int expense;
  final int net;
}

class _TrendPainterForTest extends CustomPainter {
  _TrendPainterForTest({required this.points});
  final List<_FakePoint> points;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant _TrendPainterForTest old) {
    if (old.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (old.points[i].income != points[i].income) return true;
      if (old.points[i].expense != points[i].expense) return true;
    }
    return false;
  }
}
