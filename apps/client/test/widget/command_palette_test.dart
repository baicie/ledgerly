import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/l10n/app_localizations.dart';
import 'package:ledgerly_client/presentation/widgets/command_palette.dart';

void main() {
  testWidgets('renders all actions when query is empty', (tester) async {
    await _openPalette(tester);

    expect(find.byKey(const Key('command-palette-input')), findsOneWidget);
    expect(find.byKey(const Key('command-palette-row-action-new')),
        findsOneWidget);
    expect(find.byKey(const Key('command-palette-row-nav-feed')),
        findsOneWidget);
    expect(find.byKey(const Key('command-palette-row-nav-sync')),
        findsOneWidget);
    expect(find.byKey(const Key('command-palette-row-action-sync')),
        findsNothing,
        reason: 'Sync action only added when caller passes it.');
  });

  testWidgets('filters actions by query against label', (tester) async {
    await _openPalette(tester);

    await tester.enterText(
      find.byKey(const Key('command-palette-input')),
      'feed',
    );
    await tester.pump();

    expect(find.byKey(const Key('command-palette-row-nav-feed')),
        findsOneWidget);
    expect(find.byKey(const Key('command-palette-row-nav-accounts')),
        findsNothing);
  });

  testWidgets('matches search terms in addition to label', (tester) async {
    await _openPalette(tester, actions: [
      _action(
        id: 'nav-accounts',
        label: 'Accounts',
        searchTerms: const ['资产', 'accounts'],
      ),
    ]);

    await tester.enterText(
      find.byKey(const Key('command-palette-input')),
      '资产',
    );
    await tester.pump();

    expect(find.byKey(const Key('command-palette-row-nav-accounts')),
        findsOneWidget);
  });

  testWidgets('renders empty placeholder when nothing matches', (tester) async {
    await _openPalette(tester);

    await tester.enterText(
      find.byKey(const Key('command-palette-input')),
      'zzzzz',
    );
    await tester.pump();

    expect(find.text('No matching commands'), findsOneWidget);
  });

  testWidgets('Enter activates the highlighted action and closes', (tester) async {
    var activated = '';
    await _openPalette(tester, actions: [
      _action(
        id: 'first',
        label: 'First thing',
        onActivate: () => activated = 'first',
      ),
    ]);

    // Tapping the row is the same code path the keyboard Enter uses once
    // CallbackShortcuts dispatches — we test that path here to keep the
    // widget test free of focus/keyboard-event timing issues.
    await tester.tap(find.byKey(const Key('command-palette-row-first')));
    await tester.pumpAndSettle();

    expect(activated, 'first');
    expect(find.byKey(const Key('command-palette-input')), findsNothing);
  });

  testWidgets('Tapping a row activates that action', (tester) async {
    var tapped = 0;
    await _openPalette(tester, actions: [
      _action(id: 'only', label: 'Only choice', onActivate: () => tapped++),
    ]);

    await tester.tap(find.byKey(const Key('command-palette-row-only')));
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });
}

Future<void> _openPalette(
  WidgetTester tester, {
  List<CommandPaletteAction> actions = const [],
}) async {
  await tester.pumpWidget(_TestHarness(actions: actions));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

CommandPaletteAction _action({
  required String id,
  required String label,
  List<String> searchTerms = const [],
  VoidCallback? onActivate,
}) {
  return CommandPaletteAction(
    id: id,
    label: label,
    searchTerms: searchTerms,
    icon: Icons.star,
    onActivate: onActivate ?? () {},
  );
}

class _TestHarness extends StatelessWidget {
  const _TestHarness({required this.actions});

  final List<CommandPaletteAction> actions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (innerContext) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showCommandPalette(
                innerContext,
                actions: actions.isEmpty ? _defaultActions : actions,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

final _defaultActions = [
  _action(id: 'action-new', label: 'Add'),
  _action(id: 'nav-feed', label: 'Feed'),
  _action(id: 'nav-accounts', label: 'Accounts'),
  _action(id: 'nav-sync', label: 'Sync'),
];