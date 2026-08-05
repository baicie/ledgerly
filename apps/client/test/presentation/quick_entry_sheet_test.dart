import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
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

  testWidgets('quick entry creates and immediately uses a new category',
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
    await tester.tap(find.byKey(const Key('category-add-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      '咖啡',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await tester.pumpAndSettle();

    expect(find.text('咖啡'), findsOneWidget);
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
  const _QuickEntryHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-quick-entry'),
          onPressed: () => openQuickEntry(context),
          child: const Text('记一笔'),
        ),
      ),
    );
  }
}
