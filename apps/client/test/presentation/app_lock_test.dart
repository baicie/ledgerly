import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/app_lock_store.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/presentation/widgets/app_lock_gate.dart';

void main() {
  testWidgets('lock overlay requires the PIN before the child is usable', (
    tester,
  ) async {
    final store = MemoryAppLockStore(pin: '1234');
    final controller = AppLockController(store: store);
    await controller.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockStoreProvider.overrideWithValue(store),
          appLockControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: AppLockGate(
            child: Scaffold(body: Text('SECRET_LEDGER')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-lock-pin')), findsOneWidget);
    expect(find.text('解锁'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('app-lock-pin')), '0000');
    await tester.tap(find.byKey(const Key('app-lock-unlock')));
    await tester.pumpAndSettle();
    expect(find.text('PIN 不正确'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('app-lock-pin')), '1234');
    await tester.tap(find.byKey(const Key('app-lock-unlock')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-lock-pin')), findsNothing);
    expect(find.text('SECRET_LEDGER'), findsOneWidget);
  });

  testWidgets('disabled lock never shows the overlay', (tester) async {
    final controller = AppLockController(store: MemoryAppLockStore());
    unawaited(controller.load());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: AppLockGate(
            child: Scaffold(body: Text('OPEN')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-lock-pin')), findsNothing);
    expect(find.text('OPEN'), findsOneWidget);
  });
}
