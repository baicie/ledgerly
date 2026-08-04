import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/config/api_endpoint.dart';
import 'package:ledgerly_client/config/api_endpoint_controller.dart';
import 'package:ledgerly_client/presentation/pages/settings_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  testWidgets('local mode keeps remote settings inactive', (tester) async {
    final auth = AuthController.local();
    final endpointController = ApiEndpointController(
      store: MemoryApiEndpointStore(),
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await endpointController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          apiEndpointProvider.overrideWithValue(null),
          apiEndpointControllerProvider.overrideWithValue(endpointController),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    expect(find.text('仅本地存储'), findsOneWidget);
    expect(find.text('未设置（仅本地存储）'), findsOneWidget);
    expect(find.byKey(const Key('settings-logout')), findsNothing);

    final syncTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('同步中心'),
        matching: find.byType(ListTile),
      ),
    );
    expect(syncTile.enabled, isFalse);
    expect(syncTile.onTap, isNull);
  });

  testWidgets('renders settings navigation', (tester) async {
    final gateway = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'plus');
    final controller = AuthController(gateway);
    await controller.restore();
    final endpointController = await _endpointController();

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
          apiEndpointControllerProvider.overrideWithValue(endpointController),
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
    final endpointController = await _endpointController();

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
          apiEndpointControllerProvider.overrideWithValue(endpointController),
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

  testWidgets('changing API logs out before persisting the new origin',
      (tester) async {
    final events = <String>[];
    final gateway = _LoggingAuthGateway(events)
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'free');
    final auth = AuthController(gateway);
    await auth.restore();
    final store = _LoggingEndpointStore(events);
    final endpointController = ApiEndpointController(
      store: store,
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await endpointController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          apiEndpointProvider.overrideWithValue(
            ApiEndpoint.resolve(
              configured: 'https://one.example',
              isRelease: true,
              isWeb: false,
            ),
          ),
          apiEndpointControllerProvider.overrideWithValue(endpointController),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    await tester.tap(find.byKey(const Key('settings-api-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      'https://two.example',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-api-confirm')));
    await tester.pumpAndSettle();

    expect(events, ['logout', 'persist:https://two.example']);
    expect(auth.state.status, AuthStatus.signedOut);
    expect(endpointController.state.endpoint?.baseUrl, 'https://two.example');
  });

  testWidgets('clearing API logs out before persisting local mode',
      (tester) async {
    final events = <String>[];
    final gateway = _LoggingAuthGateway(events)
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'free');
    final auth = AuthController(gateway);
    await auth.restore();
    final store = _LoggingEndpointStore(events);
    final endpointController = ApiEndpointController(
      store: store,
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await endpointController.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          apiEndpointProvider.overrideWithValue(
            ApiEndpoint.resolve(
              configured: 'https://one.example',
              isRelease: true,
              isWeb: false,
            ),
          ),
          apiEndpointControllerProvider.overrideWithValue(endpointController),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    await tester.tap(find.byKey(const Key('settings-api-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      '',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-api-confirm')));
    await tester.pumpAndSettle();

    expect(events, ['logout', 'persist:']);
    expect(auth.state.status, AuthStatus.signedOut);
    expect(endpointController.state.isLocal, isTrue);
  });
}

Future<ApiEndpointController> _endpointController() async {
  final controller = ApiEndpointController(
    store: MemoryApiEndpointStore(
      initialValue: 'https://api.ledgerly.example',
    ),
    buildDefault: '',
    isRelease: true,
    isWeb: false,
  );
  await controller.load();
  return controller;
}

final class _LoggingAuthGateway extends FakeAuthGateway {
  _LoggingAuthGateway(this.events);

  final List<String> events;

  @override
  Future<void> logout() async {
    events.add('logout');
    await super.logout();
  }
}

final class _LoggingEndpointStore extends MemoryApiEndpointStore {
  _LoggingEndpointStore(this.events)
      : super(initialValue: 'https://one.example');

  final List<String> events;

  @override
  Future<void> write(String value) async {
    events.add('persist:$value');
    await super.write(value);
  }
}
