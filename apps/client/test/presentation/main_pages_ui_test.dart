import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
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
    tester.view.physicalSize = const Size(390, 844);
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
            onCategories: () {},
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
    expect(find.text('应用锁'), findsNothing);
    expect(find.text('订阅权益'), findsNothing);
    expect(find.text('汇率'), findsNothing);
    expect(find.text('家庭共享'), findsNothing);
    expect(find.text('预算'), findsNothing);
    expect(find.text('周期记账'), findsNothing);
    expect(find.text('附件'), findsNothing);
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
        ],
        child: const MaterialApp(home: ReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本月收支统计'), findsOneWidget);
    expect(find.textContaining('配置 DeepSeek API Key'), findsWidgets);

    await tester.scrollUntilVisible(find.text('收入来源'), 300);
    await tester.pump();
    expect(find.text('收入来源'), findsOneWidget);
    expect(find.text('工资收入'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('支出分布'), 260);
    await tester.pump();

    expect(find.text('支出分布'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
  });
}

double _cardInset(WidgetTester tester, String label) {
  final text = find.text(label);
  final card = find.ancestor(of: text, matching: find.byType(Card));
  expect(text, findsOneWidget);
  expect(card, findsOneWidget);
  return tester.getTopLeft(text).dx - tester.getTopLeft(card).dx;
}
