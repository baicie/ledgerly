import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/presentation/pages/category_editor_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/presentation/quick_entry.dart';
import 'package:ledgerly_client/presentation/quick_entry_sheet.dart';
import 'package:ledgerly_client/presentation/widgets/quick_entry_keypad.dart';

void main() {
  testWidgets('quick entry switches between expense income and transfer fields',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: const MaterialApp(home: Scaffold(body: QuickEntrySheet())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('支出'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);
    expect(find.text('转账'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('25.00'), findsNothing);
    expect(find.text('快速支出'), findsNothing);

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('工资收入'), findsOneWidget);
    expect(find.text('保存收入'), findsOneWidget);

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    expect(find.text('转出账户'), findsOneWidget);
    expect(find.text('转入账户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick entry keypad saves an income transaction', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'quick-entry-device',
    );
    await repository.seedIfEmpty();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerAppServiceProvider.overrideWithValue(
            LedgerAppService(repository),
          ),
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: const MaterialApp(home: _QuickEntryHost()),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(QuickEntrySheet)).height, lessThan(660));
    await tester.tap(find.text('收入'));
    await tester.tap(find.byKey(const Key('quick-key-1')));
    await tester.tap(find.byKey(const Key('quick-key-2')));
    await tester.tap(find.byKey(const Key('quick-key-decimal')));
    await tester.tap(find.byKey(const Key('quick-key-3')));
    await tester.pump();

    expect(find.text('12.30'), findsOneWidget);
    await tester.tap(find.text('保存收入'));
    await tester.pumpAndSettle();

    final summary = (await repository.watchSummariesSync(defaultBookId)).single;
    expect(summary.kind, TransactionSummaryKind.income);
    expect(summary.amountMinor, BigInt.from(1230));
  });

  testWidgets('quick entry saves a new transaction for yesterday',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'backfill-entry-device',
    );
    await repository.seedIfEmpty();
    final service = LedgerAppService(repository);
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerAppServiceProvider.overrideWithValue(service),
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: const MaterialApp(home: _QuickEntryHost()),
      ),
    );
    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-entry-date')));
    await tester.pumpAndSettle();
    if (yesterday.month != now.month || yesterday.year != now.year) {
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${yesterday.day}').last);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-key-1')));
    await tester.tap(find.byKey(const Key('quick-entry-save')));
    await tester.pumpAndSettle();

    final summary = (await repository.watchSummariesSync(defaultBookId)).single;
    final localDate = summary.occurredAt.toLocal();
    expect(localDate.year, yesterday.year);
    expect(localDate.month, yesterday.month);
    expect(localDate.day, yesterday.day);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing an existing transaction pre-fills and updates it',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'edit-entry-device',
    );
    await repository.seedIfEmpty();
    final service = LedgerAppService(repository);
    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(1250),
      description: 'Lunch',
    );
    final transaction =
        (await repository.watchSummariesSync(defaultBookId)).single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(repository),
          ledgerAppServiceProvider.overrideWithValue(service),
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: MaterialApp(
          home: _QuickEntryHost(transaction: transaction),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();

    expect(find.text('编辑流水'), findsOneWidget);
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('quick-entry-note')),
      'Dinner',
    );
    await tester.tap(find.byKey(const Key('quick-entry-save')));
    await tester.pumpAndSettle();

    final updated = (await repository.watchSummariesSync(defaultBookId)).single;
    expect(updated.id, transaction.id);
    expect(updated.amountMinor, BigInt.from(1250));
    expect(updated.description, 'Dinner');
    final pending = await repository.listPending(defaultBookId);
    expect(pending, hasLength(1));
    expect(pending.single.operation, 'create');
    expect(
      (jsonDecode(pending.single.payloadJson) as Map)['description'],
      'Dinner',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick entry changes the transaction date and keeps its time',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'edit-date-device',
    );
    await repository.seedIfEmpty();
    final service = LedgerAppService(repository);
    final originalLocalTime = DateTime(2024, 4, 13, 12, 34, 56);
    await service.createExpense(
      expenseAccountId: accountKeyFood(defaultBookId),
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(1800),
      description: 'Forgotten lunch',
      occurredAt: originalLocalTime.toUtc(),
    );
    final transaction =
        (await repository.watchSummariesSync(defaultBookId)).single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(repository),
          ledgerAppServiceProvider.overrideWithValue(service),
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: MaterialApp(
          home: _QuickEntryHost(transaction: transaction),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();

    expect(find.text('2024年4月13日'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('quick-entry-date')));
    await tester.tap(find.byKey(const Key('quick-entry-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('14'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('2024年4月14日'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-entry-save')));
    await tester.pumpAndSettle();

    final updated = (await repository.watchSummariesSync(defaultBookId)).single;
    final updatedLocalTime = updated.occurredAt.toLocal();
    expect(updatedLocalTime.year, 2024);
    expect(updatedLocalTime.month, 4);
    expect(updatedLocalTime.day, 14);
    expect(updatedLocalTime.hour, originalLocalTime.hour);
    expect(updatedLocalTime.minute, originalLocalTime.minute);
    expect(updatedLocalTime.second, originalLocalTime.second);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick entry creates and immediately uses a new child category',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'quick-category-device',
    );
    await repository.seedIfEmpty();
    final service = LedgerAppService(repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(repository),
          ledgerAppServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: _QuickEntryHost()),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-category-field')));
    await tester.pumpAndSettle();

    expect(find.text('一级分类'), findsWidgets);
    expect(find.text('餐饮 · 二级分类'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('category-add-picker')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryEditorPage), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      '咖啡',
    );
    await tester.tap(find.text('二级分类'));
    await tester.pump();
    expect(find.byKey(const Key('category-parent-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('category-save')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryEditorPage), findsNothing);
    expect(find.text('咖啡'), findsOneWidget);
    final categories =
        await repository.listCategories(defaultBookId, 'expense');
    final coffee = categories.singleWhere((category) => category.name == '咖啡');
    expect(coffee.parentAccountId, accountKeyFood(defaultBookId));
    await tester.tap(find.byKey(const Key('quick-key-2')));
    await tester.tap(find.byKey(const Key('quick-entry-save')));
    await tester.pumpAndSettle();

    final summary = (await repository.watchSummariesSync(defaultBookId)).single;
    expect(summary.categoryName, '咖啡');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('quick entry remains usable in a short landscape viewport',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: const MaterialApp(home: _QuickEntryHost()),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('quick-entry-note')));
    await tester.tap(find.byKey(const Key('quick-entry-note')));
    await tester.pump();

    expect(find.byType(QuickEntryKeypad), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(QuickEntryKeypad), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _accounts = [
  AccountBalanceRow(
    id: accountKeyCash(defaultBookId),
    name: 'Cash',
    type: 'asset',
    balance: BigInt.zero,
  ),
  AccountBalanceRow(
    id: accountKeyBank(defaultBookId),
    name: 'Bank',
    type: 'asset',
    balance: BigInt.zero,
  ),
  AccountBalanceRow(
    id: accountKeyFood(defaultBookId),
    name: 'Food',
    type: 'expense',
    balance: BigInt.zero,
  ),
  AccountBalanceRow(
    id: accountKeySalary(defaultBookId),
    name: 'Salary',
    type: 'income',
    balance: BigInt.zero,
  ),
];

class _QuickEntryHost extends StatelessWidget {
  const _QuickEntryHost({this.transaction});

  final TransactionSummary? transaction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-quick-entry'),
          onPressed: () => openQuickEntry(context, transaction: transaction),
          child: const Text('记一笔'),
        ),
      ),
    );
  }
}
