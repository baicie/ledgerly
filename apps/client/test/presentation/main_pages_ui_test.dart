import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/pages/accounts_page.dart';
import 'package:ledgerly_client/presentation/pages/reports_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/presentation/widgets/settings_content.dart';

void main() {
  testWidgets('accounts page shows localized asset accounts and net worth', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBalancesProvider.overrideWith(
            (ref) async => [
              AccountBalanceRow(
                id: 'cash',
                name: 'Cash',
                type: 'asset',
                balance: BigInt.from(123456),
              ),
              AccountBalanceRow(
                id: 'food',
                name: 'Food',
                type: 'expense',
                balance: BigInt.from(4200),
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('净资产'), findsOneWidget);
    expect(find.text('1,234.56'), findsOneWidget);
    expect(find.text('现金'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing);
    expect(_cardInset(tester, '账户明细'), 20);
  });

  testWidgets('settings group headings keep a card edge inset', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsContent(
            isLocal: true,
            endpointLabel: '未设置（仅本地存储）',
            loggingOut: false,
            changingEndpoint: false,
            onChangeEndpoint: () {},
            onSync: null,
            onConflicts: null,
            onExport: () {},
            onImport: () {},
            onCategories: () {},
            onBudgets: () {},
            onRecurring: () {},
            onAttachments: () {},
            onLock: () {},
            onAi: () {},
            onLogout: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_cardInset(tester, '数据与同步'), 20);
    expect(find.text('分类管理'), findsOneWidget);
    expect(find.text('AI 消费总结'), findsOneWidget);
    expect(find.text('同步中心'), findsNothing);
    expect(find.text('冲突处理'), findsNothing);
    expect(find.text('应用锁'), findsOneWidget);
    expect(find.text('订阅权益'), findsNothing);
    expect(find.text('汇率'), findsNothing);
    expect(find.text('家庭共享'), findsNothing);
    expect(find.text('预算目标'), findsOneWidget);
    expect(find.text('周期记账'), findsOneWidget);
    expect(find.text('附件上传'), findsOneWidget);
  });

  testWidgets('remote settings exposes the budget target entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsContent(
            isLocal: false,
            endpointLabel: 'https://ledger.example',
            loggingOut: false,
            changingEndpoint: false,
            onChangeEndpoint: () {},
            onSync: () {},
            onConflicts: () {},
            onExport: () {},
            onCategories: () {},
            onBudgets: () {},
            onAi: () {},
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('预算目标'), findsOneWidget);
  });

  testWidgets('reports page presents monthly income and expense sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiEndpointProvider.overrideWithValue(null),
          aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
          monthTransactionsProvider.overrideWith(
            (ref) async => [
              TransactionSummary(
                id: 'income',
                occurredAt: DateTime.utc(2026, 8, 4),
                description: 'Salary',
                entryCount: 2,
                kind: TransactionSummaryKind.income,
                amountMinor: BigInt.from(1000000),
                categoryName: 'Salary',
                accountName: 'Bank',
              ),
              TransactionSummary(
                id: 'expense',
                occurredAt: DateTime.utc(2026, 8, 4),
                description: 'Dinner',
                entryCount: 2,
                kind: TransactionSummaryKind.expense,
                amountMinor: BigInt.from(5500),
                categoryName: 'Food',
                accountName: 'Cash',
              ),
            ],
          ),
          reportBudgetProvider.overrideWith((ref) async => []),
          selectedMonthAiInsightProvider.overrideWith(
            (ref) async => const AiInsightView(
              status: AiInsightStatus.ready,
              kind: InsightKind.monthly,
              periodKey: '2026-08',
              periodLabel: '2026年8月',
              headline: '测试总结',
              highlights: const ['高消费'],
              advice: const ['减少开支'],
            ),
          ),
        ],
        child: const MaterialApp(home: ReportsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    // AI card renders at top.
    expect(find.text('AI 总结'), findsOneWidget);
    expect(find.text('测试总结'), findsOneWidget);
    // Scroll to find the other sections.
    await tester.scrollUntilVisible(find.text('本月概览'), 300);
    await tester.pump();
    expect(find.text('本月概览'), findsOneWidget);
    expect(find.text('收入'), findsWidgets);
    expect(find.text('支出'), findsWidgets);
    expect(find.text('净额'), findsOneWidget);
    // Trend section title.
    await tester.scrollUntilVisible(find.text('近 6 个月趋势'), 300);
    await tester.pump();
    expect(find.text('近 6 个月趋势'), findsOneWidget);
    // Budgets section (overridden to empty in test).
    await tester.scrollUntilVisible(find.text('预算'), 300);
    expect(find.text('预算'), findsOneWidget);
  });
}

double _cardInset(WidgetTester tester, String label) {
  final text = find.text(label);
  final card = find.ancestor(of: text, matching: find.byType(Card));
  expect(text, findsOneWidget);
  expect(card, findsOneWidget);
  return tester.getTopLeft(text).dx - tester.getTopLeft(card).dx;
}
