import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/pages/feed_page.dart';
import 'package:ledgerly_client/presentation/pages/reports_page.dart';
import 'package:ledgerly_client/presentation/pages/sync_center_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('local feed opens an existing transaction for editing', (
    tester,
  ) async {
    final occurredAt = DateTime.utc(2026, 8, 4);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _booksOverride,
          apiEndpointProvider.overrideWithValue(null),
          aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
          monthTransactionsProvider.overrideWith(
            (ref) async => [
              TransactionSummary(
                id: 'tx-1',
                occurredAt: occurredAt,
                description: '午餐',
                entryCount: 2,
                kind: TransactionSummaryKind.expense,
                amountMinor: BigInt.from(1200),
                categoryName: 'Food',
                accountName: 'Cash',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: FeedPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('午餐'), findsNothing);
    expect(find.text('当日净额'), findsOneWidget);
    expect(find.text('-¥12.00'), findsOneWidget);

    await tester.tap(find.text(_dateLabel(occurredAt)));
    await tester.pumpAndSettle();

    final transactionTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('午餐'), matching: find.byType(ListTile)),
    );
    expect(transactionTile.onTap, isNotNull);
    expect(find.text('-¥12.00'), findsNWidgets(2));
  });

  testWidgets(
    'local feed keeps its header and previous data while changing month',
    (tester) async {
      final occurredAt = DateTime.utc(2026, 8, 4);
      final nextTransactions = Completer<List<TransactionSummary>>();
      final nextSummary = Completer<MonthlyLedgerSummary>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _booksOverride,
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            selectedMonthProvider.overrideWith((ref) => DateTime(2026, 8)),
            monthTransactionsProvider.overrideWith((ref) async {
              final month = ref.watch(selectedMonthProvider);
              if (month.month == 9) return nextTransactions.future;
              return [
                TransactionSummary(
                  id: 'tx-1',
                  occurredAt: occurredAt,
                  description: '午餐',
                  entryCount: 2,
                ),
              ];
            }),
            monthlyLedgerSummaryProvider.overrideWith((ref) async {
              final month = ref.watch(selectedMonthProvider);
              if (month.month == 9) return nextSummary.future;
              return MonthlyLedgerSummary(
                incomeMinor: BigInt.zero,
                expenseMinor: BigInt.from(3500),
                transactionCount: 1,
              );
            }),
          ],
          child: const MaterialApp(home: FeedPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('全部流水'), findsOneWidget);
      expect(find.text('每月分析'), findsOneWidget);
      expect(find.text(_dateLabel(occurredAt)), findsOneWidget);
      expect(find.text('午餐'), findsNothing);

      await tester.tap(find.text(_dateLabel(occurredAt)));
      await tester.pumpAndSettle();

      expect(find.text('午餐'), findsOneWidget);

      await tester.tap(find.byTooltip('下个月'));
      await tester.pump();

      expect(find.text('全部流水'), findsOneWidget);
      expect(find.text('2026年 9月'), findsOneWidget);
      expect(find.text('午餐'), findsOneWidget);

      nextTransactions.complete([]);
      nextSummary.complete(
        MonthlyLedgerSummary(
          incomeMinor: BigInt.zero,
          expenseMinor: BigInt.zero,
          transactionCount: 0,
        ),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('local reports never read the remote API provider', (
    tester,
  ) async {
    var remoteApiRead = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiEndpointProvider.overrideWithValue(null),
          aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
          categoryReportProvider.overrideWith((ref) async => []),
          syncApiProvider.overrideWith((ref) {
            remoteApiRead = true;
            throw StateError('remote API must stay inactive');
          }),
        ],
        child: const MaterialApp(home: ReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(remoteApiRead, isFalse);
    // Local-mode ReportsPage must not display remote-only plan text.
    expect(find.text('plus'), findsNothing);
  });

  testWidgets('local sync center never exposes or reads remote sync', (
    tester,
  ) async {
    var remoteSyncRead = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiEndpointProvider.overrideWithValue(null),
          syncStatusProvider.overrideWith(
            (ref) async =>
                SyncStatusView(label: '就绪', cursor: 0, pendingCount: 2),
          ),
          syncServiceProvider.overrideWith((ref) {
            remoteSyncRead = true;
            throw StateError('remote sync must stay inactive');
          }),
        ],
        child: const MaterialApp(home: SyncCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(remoteSyncRead, isFalse);
    expect(find.text('仅本地存储'), findsOneWidget);
    expect(find.text('立即同步'), findsNothing);
    expect(find.text('2 项待上传'), findsOneWidget);
  });

  testWidgets('feed source filter restricts list and badge appears', (
    tester,
  ) async {
    final occurredAt = DateTime.utc(2026, 8, 4);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _booksOverride,
          apiEndpointProvider.overrideWithValue(null),
          aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
          monthTransactionsProvider.overrideWith(
            (ref) async => [
              TransactionSummary(
                id: 'tx-auto',
                occurredAt: occurredAt,
                description: '美团外卖',
                entryCount: 2,
                kind: TransactionSummaryKind.expense,
                amountMinor: BigInt.from(2850),
                categoryName: 'Food',
                accountName: 'Cash',
                source: 'auto_ledger',
              ),
              TransactionSummary(
                id: 'tx-manual',
                occurredAt: occurredAt,
                description: '咖啡',
                entryCount: 2,
                kind: TransactionSummaryKind.expense,
                amountMinor: BigInt.from(3000),
                categoryName: 'Drinks & Snacks',
                accountName: 'Cash',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: FeedPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Expand today's transaction group so the rows are visible.
    await tester.tap(find.text(_dateLabel(occurredAt)));
    await tester.pumpAndSettle();

    // Both rows visible by default, and the auto-ledged row shows its badge.
    expect(find.text('美团外卖'), findsOneWidget);
    expect(find.text('咖啡'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auto-ledger-badge-tx-auto')),
      findsOneWidget,
    );
    expect(find.text('本月总览'), findsOneWidget);

    // Switch to auto-ledger only.
    await tester.tap(find.text('自动'));
    await tester.pumpAndSettle();
    expect(find.text('美团外卖'), findsOneWidget);
    expect(find.text('咖啡'), findsNothing);
    expect(find.text('本月自动入账'), findsOneWidget);

    // Switch to manual only.
    await tester.tap(find.text('手动'));
    await tester.pumpAndSettle();
    expect(find.text('咖啡'), findsOneWidget);
    expect(find.text('美团外卖'), findsNothing);
    expect(find.text('本月手动入账'), findsOneWidget);

    // Back to all.
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('美团外卖'), findsOneWidget);
    expect(find.text('咖啡'), findsOneWidget);
    expect(find.text('本月总览'), findsOneWidget);
  });
}

Override get _booksOverride => booksProvider.overrideWith(
  (ref) async => [
    Book(
      id: defaultBookId,
      name: 'Personal',
      currencyCode: 'CNY',
      createdAt: DateTime.utc(2026),
    ),
  ],
);

String _dateLabel(DateTime occurredAt) {
  final date = occurredAt.toLocal();
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}
