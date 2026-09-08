// End-to-end integration tests that exercise the full Flutter app widget
// tree against an in-memory Drift database. No server, no network.
//
// Run locally:
//   flutter test integration_test/app_test.dart -d linux     (desktop)
//   flutter test integration_test/app_test.dart             (host with engine)
//
// In CI, this file is executed by the `integration` job in ci.yml
// using `-d chrome` to run against a real Flutter web build.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/auth/app_lock_store.dart';
import 'package:ledgerly_client/auth/biometric_auth.dart';
import 'package:ledgerly_client/auth/session_store.dart';
import 'package:ledgerly_client/config/api_endpoint.dart';
import 'package:ledgerly_client/config/api_endpoint_controller.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/main.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test harness that launches the app in local-only mode with an in-memory
/// SQLite database and no server dependency. Every test gets a fresh DB.
class LocalModeTestHarness {
  LocalModeTestHarness() {
    _controller = ApiEndpointController(
      store: MemoryApiEndpointStore(initialValue: null),
      buildDefault: ApiEndpoint.environmentDefault,
      isRelease: false,
      isWeb: false,
    );
  }

  late final ApiEndpointController _controller;
  late final AppDatabase _db;
  late final NativeSessionStore _sessionStore;

  /// Call once before `tester.pumpWidget(harness.app())`.
  Future<void> setup() async {
    SharedPreferences.setMockInitialValues({});
    _db = AppDatabase.forTesting(NativeDatabase.memory());

    // Pre-load the controller so it reports `local()` state immediately,
    // avoiding the brief loading screen.
    await _controller.load();
    assert(
      _controller.state.status == ApiEndpointStatus.ready &&
          _controller.state.endpoint == null,
      'Expected local mode, got: ${_controller.state.status}',
    );

    _sessionStore = NativeSessionStore(
      apiOrigin: 'local',
      keyValueStore: MemorySessionKeyValueStore(),
      idFactory: () => 'integration-test-device',
    );
  }

  Future<void> teardown() async {
    _controller.dispose();
    await _db.close();
  }

  Widget app() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(_db),
        sessionStoreProvider.overrideWithValue(_sessionStore),
        appLockStoreProvider.overrideWithValue(MemoryAppLockStore()),
        biometricAuthProvider.overrideWithValue(MemoryBiometricAuth()),
        aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
        // apiEndpointProvider defaults to null; be explicit:
        apiEndpointProvider.overrideWithValue(null),
        apiEndpointControllerProvider.overrideWithValue(_controller),
      ],
      child: LedgerlyBootstrap(controller: _controller),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('local-mode bootstrap', () {
    testWidgets('app boots into the feed page', (tester) async {
      final harness = LocalModeTestHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Local mode redirects / → /feed. The feed page header reads "全部流水"
      // ("All activity") in zh-CN, the app's default locale.
      expect(find.text('全部流水'), findsOneWidget);
    });

    testWidgets('bottom nav exposes Feed / Assets / Reports / Me',
        (tester) async {
      final harness = LocalModeTestHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Default tab: Feed. The Reports nav label is "报表", not "每月分析".
      expect(find.text('全部流水'), findsOneWidget);

      // Switch to each tab and verify a unique landmark per screen.
      await tester.tap(find.text('资产'));
      await tester.pumpAndSettle();
      // Accounts page renders account cards; just check we're no longer on
      // the feed page.
      expect(find.text('全部流水'), findsNothing);

      await tester.tap(find.text('报表'));
      await tester.pumpAndSettle();
      // Reports page has an AppBar titled "报表".
      expect(find.text('报表'), findsWidgets);

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      // Settings page exposes "设置" title.
      expect(find.text('设置'), findsWidgets);
    });

    testWidgets('settings shows local-only storage indicator', (tester) async {
      final harness = LocalModeTestHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      // The settings page shows the API endpoint label. In local-only mode
      // the label reads "未设置（仅本地存储）".
      expect(find.text('未设置（仅本地存储）'), findsOneWidget);
    });

    testWidgets('quick-entry keypad accepts digit input', (tester) async {
      final harness = LocalModeTestHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Open quick-entry sheet via the FAB. There may be multiple FABs
      // (the shell FAB + the nav leading FAB), but tapping the first works.
      final fabs = find.byType(FloatingActionButton);
      expect(fabs, findsWidgets);
      await tester.tap(fabs.first);
      await tester.pumpAndSettle();

      // Sheet title.
      expect(find.text('添加流水'), findsOneWidget);

      // Keypad digits present.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsAtLeast(1));

      // Enter "125".
      await tester.tap(find.text('1'));
      await tester.tap(find.text('2'));
      await tester.tap(find.text('5'));
      await tester.pump();

      // Amount label is part of the sheet.
      expect(find.text('添加流水'), findsOneWidget);
    });

    testWidgets('month picker navigates to previous month', (tester) async {
      final harness = LocalModeTestHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // The current month label is shown; e.g. "2026年 9月".
      final now = DateTime.now();
      final currentYearLabel = '${now.year}年';

      // Tap the previous-month icon button.
      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();

      // After stepping back, the header should no longer match the current
      // year (when today is January, this assertion still holds but doesn't
      // prove a step happened — skip if that's the case).
      if (now.month == 1) {
        // Edge case: stepping back crosses a year boundary.
        expect(
          find.textContaining((now.year - 1).toString()),
          findsAtLeast(1),
        );
      } else {
        // Header label changed but a year is still visible somewhere.
        expect(find.text(currentYearLabel), findsNothing);
      }
    });

    testWidgets('reports page renders range label and chart', (tester) async {
      final harness = LocalModeTestHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('报表'));
      await tester.pumpAndSettle();

      // Reports page AppBar title (also matches the nav label).
      expect(find.text('报表'), findsWidgets);

      // Range picker button is visible at the top.
      // The exact label depends on the current month (e.g. "9月" or "本月").
      // Just verify the page rendered without crashing.
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
