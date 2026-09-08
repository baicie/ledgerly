import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/amount_parse.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/l10n/l10n.dart';
import 'package:ledgerly_client/presentation/widgets/bulk_unparsed_rescue_sheet.dart';
import 'package:ledgerly_client/services/payment_notification_service.dart';

UnparsedPaymentEvent _unparsed(
  String id, {
  String reasonTag = 'no_amount',
}) {
  return UnparsedPaymentEvent(
    id: id,
    packageName: 'com.example.bank',
    platform: 'wechat',
    reasonTag: reasonTag,
    rawText: 'Notification $id',
    timestamp: DateTime(2026, 1, 1).millisecondsSinceEpoch,
  );
}

/// Wraps the sheet in a Navigator observer so the test can pull the
/// [BulkUnparsedRescueResult] that the sheet pops back. This mirrors
/// how the production caller (`AutoLedgerSettingsPage._bulkRescueSelected`)
/// consumes the result.
class _SheetHarness {
  _SheetHarness({required this.events});
  final List<UnparsedPaymentEvent> events;
  BulkUnparsedRescueResult? lastResult;
}

Future<_SheetHarness> _openSheet(
  WidgetTester tester, {
  required List<UnparsedPaymentEvent> events,
}) async {
  tester.view.physicalSize = const Size(414, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final navigatorKey = GlobalKey<NavigatorState>();
  final harness = _SheetHarness(events: events);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-bulk-sheet'),
                onPressed: () async {
                  final result = await showBulkUnparsedRescueSheet(
                    context: context,
                    events: events,
                  );
                  harness.lastResult = result;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-bulk-sheet')));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('total preview is hidden until the user enters a valid amount',
      (tester) async {
    await _openSheet(
      tester,
      events: [
        _unparsed('a'),
        _unparsed('b'),
        _unparsed('c'),
      ],
    );
    // No preview yet because no amount is entered.
    expect(find.byKey(const Key('bulk-rescue-total-preview')), findsNothing);

    // Typing a non-numeric value should still hide the preview (parse
    // returns null).
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      'abc',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bulk-rescue-total-preview')), findsNothing);

    // Once the user enters a valid amount, the preview appears with
    // the per-event multiplier.
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      '200',
    );
    await tester.pumpAndSettle();
    final preview = find.byKey(const Key('bulk-rescue-total-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(
        of: preview,
        matching: find.text('3 entries × ¥200 = ¥600'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('total preview updates live as the amount changes',
      (tester) async {
    final harness = await _openSheet(
      tester,
      events: [_unparsed('a'), _unparsed('b')],
    );
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      '100.50',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('2 entries × ¥100.50 = ¥201'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      '12.34',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('2 entries × ¥12.34 = ¥24.68'),
      findsOneWidget,
    );
    expect(harness.lastResult, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'submitting the sheet returns a result that includes amount, merchant and category',
      (tester) async {
    final harness = await _openSheet(
      tester,
      events: [_unparsed('a'), _unparsed('b'), _unparsed('c')],
    );
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      '50',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-merchant')),
      '中石化',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bulk-rescue-submit')));
    await tester.pumpAndSettle();

    final result = harness.lastResult;
    expect(result, isNotNull);
    expect(result!.amountMinor, parsePositiveAmountMinor('50'));
    expect(result.merchant, '中石化');
    expect(result.categoryAccountId, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects invalid amounts and keeps the sheet open',
      (tester) async {
    final harness = await _openSheet(
      tester,
      events: [_unparsed('a'), _unparsed('b')],
    );
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      '',
    );
    await tester.tap(find.byKey(const Key('bulk-rescue-submit')));
    await tester.pumpAndSettle();
    expect(harness.lastResult, isNull);
    // The sheet must remain visible — no pop happened.
    expect(find.byKey(const Key('bulk-rescue-submit')), findsOneWidget);
    expect(find.byKey(const Key('bulk-rescue-total-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'enabling the learn-rule toggle is blocked for the default category unless another category is picked',
      (tester) async {
    final harness = await _openSheet(
      tester,
      events: [_unparsed('a'), _unparsed('b')],
    );
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-amount')),
      '12.34',
    );
    await tester.enterText(
      find.byKey(const Key('bulk-rescue-merchant')),
      '便利店',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bulk-rescue-learn-rule')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bulk-rescue-submit')));
    await tester.pumpAndSettle();

    // The default "Other Expense" category is treated as the catch-all;
    // even with the toggle ON we deliberately skip storing a rule for
    // it (it would never fire because all expenses match the fallback).
    final store = MerchantRuleStore();
    final rules = await store.load();
    expect(
      rules.any((rule) => rule.needles.contains('便利店')),
      isFalse,
      reason:
          'Other Expense is excluded; pick a specific category to opt in.',
    );
    expect(harness.lastResult, isNotNull);
    expect(harness.lastResult!.learnedRule, isNull);
    expect(tester.takeException(), isNull);
  });
}
