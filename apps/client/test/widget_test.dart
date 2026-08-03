import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/config/api_endpoint.dart';
import 'package:ledgerly_client/presentation/pages/settings_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  testWidgets('renders settings navigation', (tester) async {
    final gateway = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'plus');
    final controller = AuthController(gateway);
    await controller.restore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
          apiEndpointProvider.overrideWithValue(
            ApiEndpoint.resolve(
              configured: 'https://api.ledgerly.example',
              isRelease: false,
              isWeb: false,
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    expect(find.text('Plus'), findsOneWidget);
    expect(find.text('https://api.ledgerly.example'), findsOneWidget);
    expect(find.text('同步中心'), findsOneWidget);
    expect(find.text('冲突处理'), findsOneWidget);
  });

  testWidgets('logout requires confirmation', (tester) async {
    final gateway = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'free');
    final controller = AuthController(gateway);
    await controller.restore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
          apiEndpointProvider.overrideWithValue(
            ApiEndpoint.resolve(
              configured: 'https://api.ledgerly.example',
              isRelease: false,
              isWeb: false,
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-logout')),
      200,
    );
    await tester.tap(find.byKey(const Key('settings-logout')));
    await tester.pumpAndSettle();
    expect(find.text('确认退出登录？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gateway.logoutCalled, isFalse);

    await tester.tap(find.byKey(const Key('settings-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录').last);
    await tester.pumpAndSettle();

    expect(gateway.logoutCalled, isTrue);
    expect(controller.state.status, AuthStatus.signedOut);
  });
}
