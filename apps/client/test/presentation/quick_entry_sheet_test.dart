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
