import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/presentation/widgets/feed_transaction_list.dart';

void main() {
  test('daily total is negative when a day only has expenses', () {
    final total = dailyNetMinor([
      _summary(TransactionSummaryKind.expense, 4200),
      _summary(TransactionSummaryKind.expense, 1800),
    ]);

    expect(total, BigInt.from(-6000));
  });

  test('daily total subtracts expenses from income', () {
    final total = dailyNetMinor([
      _summary(TransactionSummaryKind.income, 10000),
      _summary(TransactionSummaryKind.expense, 2500),
    ]);

    expect(total, BigInt.from(7500));
  });

  testWidgets('historical days default to a collapsed daily overview',
      (tester) async {
    final historicalDay = _dayOffsetFromToday(-2);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'historical-income',
            occurredAt: historicalDay,
            description: 'Historical income',
            kind: TransactionSummaryKind.income,
            amountMinor: 10000,
          ),
          _datedSummary(
            id: 'historical-expense',
            occurredAt: historicalDay,
            description: 'Historical expense',
            kind: TransactionSummaryKind.expense,
            amountMinor: 2500,
          ),
        ],
      ),
    );

    expect(find.text(_dateLabel(historicalDay)), findsOneWidget);
    expect(find.text('当日净额'), findsOneWidget);
    expect(find.text('+¥75.00'), findsOneWidget);
    expect(find.text('Historical income'), findsNothing);
    expect(find.text('Historical expense'), findsNothing);
  });

  testWidgets("today's group defaults to expanded", (tester) async {
    final today = _dayOffsetFromToday(0);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'today-expense',
            occurredAt: today,
            description: 'Today expense',
            kind: TransactionSummaryKind.expense,
            amountMinor: 1800,
          ),
        ],
      ),
    );

    expect(find.text(_dateLabel(today)), findsOneWidget);
    expect(find.text('Today expense'), findsOneWidget);
  });

  testWidgets('today insight is inserted into the expanded today group',
      (tester) async {
    final today = _dayOffsetFromToday(0);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'today-expense',
            occurredAt: today,
            description: 'Today expense',
            kind: TransactionSummaryKind.expense,
            amountMinor: 1800,
          ),
        ],
        todayInsight: const Text('TODAY_INSIGHT'),
      ),
    );

    expect(find.text('TODAY_INSIGHT'), findsOneWidget);
    expect(find.text('Today expense'), findsOneWidget);
  });

  testWidgets('today insight still appears when today has no transactions',
      (tester) async {
    final historicalDay = _dayOffsetFromToday(-2);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'historical-income',
            occurredAt: historicalDay,
            description: 'Historical income',
            kind: TransactionSummaryKind.income,
            amountMinor: 10000,
          ),
        ],
        todayInsight: const Text('TODAY_INSIGHT'),
      ),
    );

    expect(find.text('TODAY_INSIGHT'), findsOneWidget);
  });

  testWidgets('unconfigured today insight is not orphaned above other days',
      (tester) async {
    final historicalDay = _dayOffsetFromToday(-2);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'historical-income',
            occurredAt: historicalDay,
            description: 'Historical income',
            kind: TransactionSummaryKind.income,
            amountMinor: 10000,
          ),
        ],
        todayInsight: const Text('TODAY_INSIGHT'),
        orphanTodayInsight: false,
      ),
    );

    expect(find.text('TODAY_INSIGHT'), findsNothing);
    expect(find.text(_dateLabel(historicalDay)), findsOneWidget);
  });

  testWidgets('tapping a historical day toggles its transactions',
      (tester) async {
    final historicalDay = _dayOffsetFromToday(-1);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'historical-coffee',
            occurredAt: historicalDay,
            description: 'Historical coffee',
            kind: TransactionSummaryKind.expense,
            amountMinor: 3200,
          ),
        ],
      ),
    );

    expect(find.text('Historical coffee'), findsNothing);

    await tester.tap(find.text(_dateLabel(historicalDay)));
    await tester.pumpAndSettle();

    expect(find.text('Historical coffee'), findsOneWidget);

    await tester.tap(find.text(_dateLabel(historicalDay)));
    await tester.pumpAndSettle();

    expect(find.text('Historical coffee'), findsNothing);
  });

  testWidgets('search expands historical days so matches are visible',
      (tester) async {
    final historicalDay = _dayOffsetFromToday(-2);

    await tester.pumpWidget(
      _feed(
        [
          _datedSummary(
            id: 'historical-coffee',
            occurredAt: historicalDay,
            description: 'Historical coffee',
            kind: TransactionSummaryKind.expense,
            amountMinor: 3200,
          ),
        ],
        expandAll: true,
      ),
    );

    expect(find.text('Historical coffee'), findsOneWidget);
  });
}

Widget _feed(
  List<TransactionSummary> transactions, {
  Widget? todayInsight,
  bool orphanTodayInsight = true,
  bool expandAll = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          FeedTransactionList(
            transactions: transactions,
            todayInsight: todayInsight,
            orphanTodayInsight: orphanTodayInsight,
            expandAll: expandAll,
            onOpen: (_) {},
            onDelete: (_) {},
          ),
        ],
      ),
    ),
  );
}

DateTime _dayOffsetFromToday(int dayOffset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + dayOffset, 12);
}

String _dateLabel(DateTime date) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}

TransactionSummary _datedSummary({
  required String id,
  required DateTime occurredAt,
  required String description,
  required TransactionSummaryKind kind,
  required int amountMinor,
}) {
  return TransactionSummary(
    id: id,
    occurredAt: occurredAt,
    description: description,
    entryCount: 2,
    kind: kind,
    amountMinor: BigInt.from(amountMinor),
    categoryName: 'Food',
    accountName: 'Cash',
  );
}

TransactionSummary _summary(TransactionSummaryKind kind, int amountMinor) {
  return TransactionSummary(
    id: '$kind-$amountMinor',
    occurredAt: DateTime.utc(2026, 8, 4),
    description: 'test',
    entryCount: 2,
    kind: kind,
    amountMinor: BigInt.from(amountMinor),
  );
}
