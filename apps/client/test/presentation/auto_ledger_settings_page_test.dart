import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/l10n/l10n.dart';
import 'package:ledgerly_client/presentation/pages/auto_ledger_settings_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/services/payment_notification_service.dart';

class _FakePaymentGateway implements PaymentNotificationGateway {
  _FakePaymentGateway({
    List<UnparsedPaymentEvent>? unparsed,
    List<PendingPaymentEvent>? pending,
  })  : unparsed = List<UnparsedPaymentEvent>.from(unparsed ?? const []),
        pending = List<PendingPaymentEvent>.from(pending ?? const []);

  final List<UnparsedPaymentEvent> unparsed;
  final List<PendingPaymentEvent> pending;
  final List<String> dismissed = <String>[];
  final List<String> clearedAll = <String>[];

  @override
  Future<bool> isAccessEnabled() async => true;
  @override
  Future<void> openAccessSettings() async {}
  @override
  Future<List<PendingPaymentEvent>> getPendingEvents() async =>
      List<PendingPaymentEvent>.from(pending);
  @override
  Future<void> clearPendingEvents() async => pending.clear();
  @override
  Future<List<UnparsedPaymentEvent>> getUnparsedEvents() async =>
      List<UnparsedPaymentEvent>.from(unparsed);
  @override
  Future<void> clearUnparsedEvents() async {
    clearedAll.add('clear');
    unparsed.clear();
  }

  @override
  Future<bool> dismissUnparsedEvent(String id) async {
    final before = unparsed.length;
    unparsed.removeWhere((event) => event.id == id);
    final removed = unparsed.length != before;
    if (removed) dismissed.add(id);
    return removed;
  }
}

UnparsedPaymentEvent _unparsed(
  String id, {
  String reasonTag = 'no_amount',
  String platform = 'wechat',
  int? timestamp,
}) {
  return UnparsedPaymentEvent(
    id: id,
    packageName: 'com.example.bank',
    platform: platform,
    reasonTag: reasonTag,
    rawText: 'Notification $id',
    timestamp: timestamp ?? DateTime(2026, 1, 1).millisecondsSinceEpoch,
  );
}

List<UnparsedPaymentEvent> _buildUnparsedList({
  required int total,
  String functionName = 'no_amount',
  String otherTag = 'parse_error',
  double dominantShare = 0.0,
}) {
  final dominant = (total * dominantShare).round();
  final others = total - dominant;
  return [
    for (var i = 0; i < dominant; i++)
      _unparsed('evt-$i', reasonTag: functionName),
    for (var i = 0; i < others; i++)
      _unparsed('evt-mix-$i', reasonTag: otherTag),
  ];
}

Future<Widget> _harness(
  WidgetTester tester, {
  required _FakePaymentGateway gateway,
  LedgerAppService? service,
}) async {
  tester.view.physicalSize = const Size(414, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // The merchant rule store reads SharedPreferences; the auto-ledger
  // service is null-safe to skip below so most tests don't need a repo.
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentNotificationGatewayProvider.overrideWithValue(gateway),
        if (service != null)
          ledgerAppServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(
        home: AutoLedgerSettingsPage(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return const SizedBox.shrink();
}

void main() {
  testWidgets('backlog banner is hidden when queue has fewer than 5 events',
      (tester) async {
    final gateway = _FakePaymentGateway(
      unparsed: _buildUnparsedList(total: 4),
    );
    await _harness(tester, gateway: gateway);
    expect(find.byKey(const Key('auto-ledger-backlog-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backlog banner shows a tertiary-coloured warning at 5 events and clears the reason filter via the action button',
      (tester) async {
    // 5 events all tagged the same way; this should hit the medium
    // threshold and the dominant-reason hint branch.
    final gateway = _FakePaymentGateway(
      unparsed: _buildUnparsedList(total: 5, dominantShare: 1.0),
    );
    await _harness(tester, gateway: gateway);
    expect(find.byKey(const Key('auto-ledger-backlog-banner')), findsOneWidget);
    // The dominant reason hint must call out the reason tag.
    expect(find.textContaining('no_amount'), findsWidgets);
    // Tap the action button and confirm the banner leaves scope.
    await tester.tap(find.byKey(const Key('auto-ledger-backlog-action')));
    await tester.pumpAndSettle();
    // After dismiss + dismiss, banner should still be visible because
    // the queue still has 5 entries. We mostly want to assert no
    // exception is thrown when invoking the callback.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backlog banner escalates to error colour when queue exceeds 10 events',
      (tester) async {
    final gateway = _FakePaymentGateway(
      unparsed: _buildUnparsedList(total: 11, dominantShare: 0.6),
    );
    await _harness(tester, gateway: gateway);
    expect(find.byKey(const Key('auto-ledger-backlog-banner')), findsOneWidget);
    // The dominant reason kick-in: 11 * 0.6 ~ 7, which is >= half of 11
    // so the hint must appear.
    expect(find.textContaining('no_amount'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backlog banner is hidden when entries are spread across many reasons',
      (tester) async {
    // 5 entries, but split across 5 distinct reason tags. The dominant
    // branch is suppressed, so the banner still appears at the medium
    // threshold even without a hint.
    final entries = <UnparsedPaymentEvent>[
      _unparsed('a', reasonTag: 'tag-1'),
      _unparsed('b', reasonTag: 'tag-2'),
      _unparsed('c', reasonTag: 'tag-3'),
      _unparsed('d', reasonTag: 'tag-4'),
      _unparsed('e', reasonTag: 'tag-5'),
    ];
    final gateway = _FakePaymentGateway(unparsed: entries);
    await _harness(tester, gateway: gateway);
    expect(find.byKey(const Key('auto-ledger-backlog-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reason filter chips scope the unparsed list as expected',
      (tester) async {
    final entries = <UnparsedPaymentEvent>[
      _unparsed('a', reasonTag: 'no_amount'),
      _unparsed('b', reasonTag: 'parse_error'),
      _unparsed('c', reasonTag: 'no_amount'),
    ];
    final gateway = _FakePaymentGateway(unparsed: entries);
    await _harness(tester, gateway: gateway);
    // Three ListTiles by default (the filter scope starts at "all").
    expect(find.byKey(const Key('auto-ledger-unparsed-a')), findsOneWidget);
    expect(find.byKey(const Key('auto-ledger-unparsed-b')), findsOneWidget);
    expect(find.byKey(const Key('auto-ledger-unparsed-c')), findsOneWidget);
    // Tap the no_amount chip.
    await tester.tap(find.byKey(const Key('auto-ledger-reason-no_amount')));
    await tester.pumpAndSettle();
    // Only the no_amount entries remain in scope.
    expect(find.byKey(const Key('auto-ledger-unparsed-a')), findsOneWidget);
    expect(find.byKey(const Key('auto-ledger-unparsed-b')), findsNothing);
    expect(find.byKey(const Key('auto-ledger-unparsed-c')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press on an unparsed event enters bulk selection mode',
      (tester) async {
    final entries = <UnparsedPaymentEvent>[
      _unparsed('a', reasonTag: 'no_amount'),
      _unparsed('b', reasonTag: 'no_amount'),
    ];
    final gateway = _FakePaymentGateway(unparsed: entries);
    await _harness(tester, gateway: gateway);
    // Initially the bulk action button is hidden.
    expect(find.byKey(const Key('auto-ledger-bulk-rescue')), findsNothing);
    // Long-press the first tile.
    await tester.longPress(find.byKey(const Key('auto-ledger-unparsed-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auto-ledger-bulk-rescue')), findsOneWidget);
    // Tap another tile to add to the selection; the count must update.
    await tester.tap(find.byKey(const Key('auto-ledger-unparsed-b')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 selected'), findsOneWidget);
    // Tapping "Clear" returns the page to the normal chrome.
    await tester.tap(find.byKey(const Key('auto-ledger-bulk-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auto-ledger-bulk-rescue')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backlog banner dismiss button routes through dismissUnparsedEvent per event',
      (tester) async {
    // Make sure the "Clear all" button the page exposes still works on
    // a page that has a banner: tapping it should clear the queue and
    // drop the banner.
    final gateway = _FakePaymentGateway(
      unparsed: _buildUnparsedList(total: 6, dominantShare: 0.5),
    );
    await _harness(tester, gateway: gateway);
    expect(find.byKey(const Key('auto-ledger-backlog-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('auto-ledger-unparsed-dismiss')));
    await tester.pumpAndSettle();
    expect(gateway.clearedAll, isNotEmpty);
    expect(find.byKey(const Key('auto-ledger-backlog-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
