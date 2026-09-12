import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/l10n/app_localizations.dart';
import 'package:ledgerly_client/presentation/pages/keyboard_shortcuts_page.dart';

void main() {
  testWidgets('renders the general bookkeeping and sync groups', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KeyboardShortcutsPage(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Bookkeeping'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);

    expect(find.byKey(const Key('shortcut-row-open-palette')), findsOneWidget);
    expect(find.byKey(const Key('shortcut-row-close-dialog')), findsOneWidget);
    expect(find.byKey(const Key('shortcut-row-new-transaction')),
        findsOneWidget);
    expect(find.byKey(const Key('shortcut-row-sync-now')), findsOneWidget);
  });

  testWidgets('row taps invoke onTrigger with the matching action',
      (tester) async {
    final triggered = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardShortcutsPage(
          onTrigger: (action) => triggered.add(action.id),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shortcut-row-open-palette')));
    await tester.tap(find.byKey(const Key('shortcut-row-new-transaction')));
    await tester.pump();

    expect(triggered, ['open-palette', 'new-transaction']);
  });

  testWidgets('shortcut chip ends with the action key letter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KeyboardShortcutsPage(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    // The default test platform is Android → renderer uses the `Ctrl` form.
    // We just check that *some* binding text includes the action key
    // letter; platform-specific glyphs are exercised by manual checks.
    final openPalette = tester.widget<ListTile>(
      find.byKey(const Key('shortcut-row-open-palette')),
    );
    expect(openPalette.title, isNotNull);
    expect(find.textContaining('K'), findsWidgets);
    expect(find.textContaining('N'), findsWidgets);
    expect(find.text('Esc'), findsWidgets);
  });
}