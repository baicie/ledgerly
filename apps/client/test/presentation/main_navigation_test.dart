import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/presentation/widgets/ledgerly_navigation.dart';

void main() {
  testWidgets('quick entry is a command between four navigation branches',
      (tester) async {
    var selectedIndex = 0;
    var quickEntryOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LedgerlyBottomNavigation(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => selectedIndex = index,
            onQuickEntry: () => quickEntryOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('流水'), findsOneWidget);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('报表'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('报表'));
    expect(selectedIndex, 2);

    await tester.tap(find.byTooltip('记一笔'));
    expect(quickEntryOpened, isTrue);
    expect(selectedIndex, 2);
  });
}
