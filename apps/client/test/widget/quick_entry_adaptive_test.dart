import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/l10n/app_localizations.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/presentation/quick_entry.dart';
import 'package:ledgerly_client/presentation/utils/adaptive.dart';

/// Verifies that [openQuickEntry] picks the right container based on
/// [kWideBreakpoint]. These tests intentionally avoid the full Ledgerly
/// bootstrap so they can be run in isolation from auth and sync providers.
void main() {
  testWidgets('narrow viewport opens quick entry inside a bottom sheet',
      (tester) async {
    _setViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: const MaterialApp(
          home: _QuickEntryHost(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    // QuickEntrySheet content still mounted, just hosted inside a sheet.
    expect(find.byKey(const Key('quick-entry-save')), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide viewport opens quick entry as a centered dialog',
      (tester) async {
    _setViewport(tester, const Size(1440, 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBalancesProvider.overrideWith((ref) async => _accounts),
        ],
        child: const MaterialApp(
          home: _QuickEntryHost(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quick-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const Key('quick-entry-save')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kWideBreakpoint is 900 and isWideLayout honours it',
      (tester) async {
    expect(kWideBreakpoint, 900);

    late bool narrow;
    late bool wide;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(kWideBreakpoint - 1, 800)),
        child: Builder(
          builder: (context) {
            narrow = isWideLayout(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(kWideBreakpoint, 800)),
        child: Builder(
          builder: (context) {
            wide = isWideLayout(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(narrow, isFalse);
    expect(wide, isTrue);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

final _accounts = [
  AccountBalanceRow(
    id: accountKeyCash(defaultBookId),
    name: 'Cash',
    type: 'asset',
    balance: BigInt.zero,
  ),
  AccountBalanceRow(
    id: accountKeyFood(defaultBookId),
    name: 'Food',
    type: 'expense',
    balance: BigInt.zero,
  ),
];