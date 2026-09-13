// End-to-end "journey" tests that exercise the full app widget tree against
// an in-memory Drift database — no server, no network, no platform plugins.
//
// These tests complement the lighter-weight UI checks in `app_test.dart` by
// walking through the *critical user paths* that no smoke test should miss:
//
//   1. Record a new expense from the quick-entry sheet and see it land in
//      the feed.
//   2. Navigate to Reports and verify the hero summary reflects a seeded
//      expense (income / expense / net).
//   3. Open the budget targets page (local-mode flow) and verify the
//      "no budgets yet" CTA is visible.
//   4. Create a recurring rule whose next_run_date is today and verify the
//      scheduler posts a real transaction into the feed.
//   5. Pre-seed an app-lock PIN and verify the unlock overlay enforces it
//      before exposing the feed.
//
// Run locally (host VM):
//   flutter test integration_test/journey_test.dart
//
// CI runs the same suite under Chrome:
//   flutter test -d chrome integration_test
// (see .github/workflows/ci.yml → `integration` job)

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
import 'package:ledgerly_client/domain/default_categories.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/main.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Test harness for end-to-end journeys. Boots the app in local-only mode
/// against a fresh in-memory SQLite database, with biometric / app-lock /
/// AI stores all replaced by in-memory variants so the suite stays
/// hermetic on every platform (host VM, Chrome, mobile).
class JourneyHarness {
  JourneyHarness();

  late final ApiEndpointController controller;
  late final AppDatabase db;
  late final NativeSessionStore sessionStore;
  late final MemoryAppLockStore appLockStore;
  late final MemoryBiometricAuth biometrics;

  Future<void> setup() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());

    controller = ApiEndpointController(
      store: MemoryApiEndpointStore(initialValue: null),
      buildDefault: ApiEndpoint.environmentDefault,
      isRelease: false,
      isWeb: false,
    );
    await controller.load();
    assert(
      controller.state.status == ApiEndpointStatus.ready &&
          controller.state.endpoint == null,
      'Expected local mode, got: ${controller.state.status}',
    );

    sessionStore = NativeSessionStore(
      apiOrigin: 'local',
      keyValueStore: MemorySessionKeyValueStore(),
      idFactory: () => 'journey-test-device',
    );

    appLockStore = MemoryAppLockStore();
    biometrics = MemoryBiometricAuth();
  }

  Future<void> teardown() async {
    controller.dispose();
    await db.close();
  }

  Widget app() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionStoreProvider.overrideWithValue(sessionStore),
        appLockStoreProvider.overrideWithValue(appLockStore),
        biometricAuthProvider.overrideWithValue(biometrics),
        aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
        apiEndpointProvider.overrideWithValue(null),
        apiEndpointControllerProvider.overrideWithValue(controller),
      ],
      child: LedgerlyBootstrap(controller: controller),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------- Journey #1: quick-entry → feed → summary ----------

  testWidgets(
    'journey: recording an expense shows up in the feed',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = JourneyHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Land on the feed page.
      expect(find.text('全部流水'), findsOneWidget);
      expect(find.text('本月总览'), findsOneWidget);

      // Open the quick-entry sheet via the FAB.
      final fabs = find.byType(FloatingActionButton);
      expect(fabs, findsWidgets);
      await tester.tap(fabs.first);
      await tester.pumpAndSettle();

      // Sheet is open. The default mode is expense.
      expect(find.text('添加流水'), findsOneWidget);

      // Tap the category field (uses a stable Key) to open the picker.
      await tester.tap(find.byKey(const Key('quick-category-field')));
      await tester.pumpAndSettle();

      // Pick the Food root category. The picker builds a ListTile per
      // category with a stable Key derived from the account id.
      final foodFinder = find.byKey(
        const Key('quick-category-book_default:acc_food'),
      );
      expect(foodFinder, findsOneWidget);
      await tester.tap(foodFinder);
      await tester.pumpAndSettle();

      // Type 12.50 on the keypad.
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('.'));
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('0'));
      await tester.pump();

      // Save and confirm the sheet closes.
      await tester.tap(find.byKey(const Key('quick-entry-save')));
      await tester.pumpAndSettle();

      // The new transaction tile should now be visible in the feed. The
      // tile renders the amount with a leading "-" sign (expense) and the
      // currency symbol, e.g. "-¥12.50".
      expect(find.text('-¥12.50'), findsOneWidget);
    },
  );

  // ---------- Journey #2: reports summary reflects the new expense ----------

  testWidgets(
    'journey: reports page reflects a seeded expense in the hero summary',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = JourneyHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Seed an expense directly through the service — bypasses the UI to
      // keep this test focused on the reports path.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final service = container.read(ledgerAppServiceProvider);
      await service.createExpense(
        expenseAccountId: accountKeyFood(defaultBookId),
        fundingAccountId: accountKeyBank(defaultBookId),
        amountMinor: BigInt.from(8800), // ¥88.00
        description: 'reports-journey',
        occurredAt: DateTime.now(),
      );

      // Allow the underlying provider to pick up the new transaction.
      await tester.pumpAndSettle();

      // Navigate to Reports via the bottom nav.
      await tester.tap(find.text('报表'));
      await tester.pumpAndSettle();

      // The page title appears in the AppBar AND as a bottom-nav label.
      expect(find.text('报表'), findsWidgets);
      // The hero summary card renders the expense amount. The amount
      // appears in two places (hero stat + summary card row), so use
      // findsAtLeast to be robust against layout shifts.
      expect(find.textContaining('88.00'), findsAtLeast(1));
    },
  );

  // ---------- Journey #3: budget targets page reachable in local mode ----------

  testWidgets(
    'journey: navigating to budgets shows the empty state in local mode',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = JourneyHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Me tab.
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      // Open the budgets page from the settings list.
      await tester.tap(find.text('预算目标'));
      await tester.pumpAndSettle();

      expect(find.text('还没有预算目标'), findsOneWidget);
      expect(find.text('设置第一个目标'), findsOneWidget);
    },
  );

  // ---------- Journey #4: recurring rule posts a transaction ----------

  testWidgets(
    'journey: a due recurring rule posts a transaction via the scheduler',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = JourneyHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Insert a recurring rule whose next_run_date is today (already due).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final recurring = container.read(localRecurringRepositoryProvider);
      final today = DateTime.now();
      final todayIso =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await recurring.insert(
        bookId: defaultBookId,
        name: 'Monthly rent',
        kind: 'expense',
        amountMinor: BigInt.from(200000), // ¥2000.00
        categoryAccountId: accountKeyFood(defaultBookId),
        accountId: accountKeyBank(defaultBookId),
        dayOfMonth: today.day,
      );
      // Force the rule's next_run_date to today (insert() picks next
      // future month).
      await container.read(databaseProvider).customStatement(
            'UPDATE local_recurring_rules SET next_run_date = ? WHERE book_id = ?',
            [todayIso, defaultBookId],
          );

      // Trigger the scheduler directly. We can't rely on the FutureProvider
      // because its result is cached after the first build, and the rule
      // was inserted *after* the app had already run catchUp.
      final scheduler = container.read(recurringSchedulerProvider);
      final posted = await scheduler.catchUp();
      expect(posted, greaterThanOrEqualTo(1));
      // Drain any pending provider updates so the UI rebuilds.
      await tester.pumpAndSettle();

      // After catch-up the feed should contain the auto-posted rent.
      expect(find.text('全部流水'), findsOneWidget);
      expect(find.text('-¥2,000.00'), findsOneWidget);
    },
  );

  // ---------- Journey #5: app lock overlay ----------

  testWidgets(
    'journey: app lock overlay enforces the PIN before exposing the feed',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = JourneyHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      // Simulate the user having enabled app lock.
      await harness.appLockStore.writePin('4242');

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // The lock overlay covers the feed.
      expect(find.byKey(const Key('app-lock-pin')), findsOneWidget);
      expect(find.text('已锁定'), findsOneWidget);

      // Wrong PIN attempt → keeps the overlay and surfaces an error.
      await tester.enterText(find.byKey(const Key('app-lock-pin')), '0000');
      await tester.tap(find.byKey(const Key('app-lock-unlock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-lock-pin')), findsOneWidget);
      expect(find.text('PIN 不正确'), findsOneWidget);

      // Correct PIN → overlay disappears, feed becomes visible.
      await tester.enterText(find.byKey(const Key('app-lock-pin')), '4242');
      await tester.tap(find.byKey(const Key('app-lock-unlock')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-lock-pin')), findsNothing);
      expect(find.text('全部流水'), findsOneWidget);
    },
  );

  // ---------- Journey #6: recurring page renders for the local book ----------

  testWidgets(
    'journey: recurring page is reachable from settings',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = JourneyHarness();
      await harness.setup();
      addTearDown(harness.teardown);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // Me tab → settings → recurring.
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周期记账'));
      await tester.pumpAndSettle();

      expect(find.text('周期记账'), findsWidgets);
      expect(find.text('创建规则'), findsOneWidget);
    },
  );

  // ---------- Sanity check on the default seed ----------

  test('default categories expose a Food root for expense picker', () {
    final food =
        defaultCategoryDefinitions.where((c) => c.key == 'acc_food').single;
    expect(food.parentKey, isNull);
    expect(food.type, 'expense');
  });
}