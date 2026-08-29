import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/pages/feed_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/presentation/widgets/ledgerly_book_switcher.dart';
import 'package:ledgerly_client/presentation/widgets/ledgerly_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final books = [
    Book(
      id: defaultBookId,
      name: 'Personal',
      currencyCode: 'CNY',
      createdAt: DateTime.utc(2026),
    ),
    Book(
      id: 'book_travel',
      name: '旅行',
      currencyCode: 'CNY',
      createdAt: DateTime.utc(2026, 2),
    ),
  ];

  List<Override> overrides() => [
    booksProvider.overrideWith((ref) async => books),
  ];

  testWidgets('book switcher replaces a dropdown bar with a header menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(
          home: Scaffold(
            body: LedgerlyPageHeader(
              title: '全部流水',
              subtitleWidget: LedgerlyBookSwitcher(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部流水'), findsOneWidget);
    expect(find.text('标准账本'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.byKey(const Key('book-switcher')));
    await tester.pumpAndSettle();

    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('新建账本'), findsOneWidget);

    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();

    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('标准账本'), findsNothing);
  });

  testWidgets('feed keeps its page header and does not add a shell book bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          apiEndpointProvider.overrideWithValue(null),
          aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
          monthTransactionsProvider.overrideWith((ref) async => []),
          monthlyLedgerSummaryProvider.overrideWith(
            (ref) async => MonthlyLedgerSummary(
              incomeMinor: BigInt.zero,
              expenseMinor: BigInt.zero,
              transactionCount: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: FeedPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部流水'), findsOneWidget);
    expect(find.text('标准账本'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    final header = tester.getRect(find.text('全部流水'));
    final switcher = tester.getRect(find.text('标准账本'));
    expect(switcher.top, greaterThan(header.top));
    expect(switcher.top - header.bottom, lessThan(16));
  });
}
