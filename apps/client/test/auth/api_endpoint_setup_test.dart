import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/config/api_endpoint_controller.dart';
import 'package:ledgerly_client/main.dart';
import 'package:ledgerly_client/presentation/pages/api_endpoint_setup_page.dart';
import 'package:ledgerly_client/presentation/pages/startup_page.dart';

import '../support/fake_auth_gateway.dart';

void main() {
  testWidgets('first-run setup fits a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ApiEndpointController(
      store: MemoryApiEndpointStore(),
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ApiEndpointSetupPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接 API 服务'), findsOneWidget);
    expect(find.byKey(const Key('api-endpoint-input')), findsOneWidget);
    expect(find.byKey(const Key('api-endpoint-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release bootstrap opens setup when no endpoint exists',
      (tester) async {
    final controller = ApiEndpointController(
      store: MemoryApiEndpointStore(),
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );

    await tester.pumpWidget(LedgerlyBootstrap(controller: controller));
    await tester.pumpAndSettle();

    expect(controller.state.status, ApiEndpointStatus.needsConfiguration);
    expect(find.text('连接 API 服务'), findsOneWidget);
  });

  testWidgets('first-run setup rejects unsafe Web release URLs and saves HTTPS',
      (tester) async {
    final store = MemoryApiEndpointStore();
    final controller = ApiEndpointController(
      store: store,
      buildDefault: '',
      isRelease: true,
      isWeb: true,
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ApiEndpointSetupPage(controller: controller)),
    );

    expect(find.text('连接 API 服务'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      'http://api.example',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pump();

    expect(find.text('正式版本仅支持非本机 HTTPS 地址'), findsOneWidget);
    expect(store.value, isNull);

    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      'https://api.example:8443',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pump();

    expect(find.text('Web 正式版本仅支持 HTTPS 默认端口（443）'), findsOneWidget);
    expect(store.value, isNull);

    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      'https://api.example/',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pumpAndSettle();

    expect(store.value, 'https://api.example');
    expect(controller.state.status, ApiEndpointStatus.ready);
  });

  testWidgets('failed startup lets the user correct the API endpoint',
      (tester) async {
    final auth = AuthController(_FailingRestoreGateway());
    addTearDown(auth.dispose);
    await auth.restore();
    final endpoint = ApiEndpointController(
      store: MemoryApiEndpointStore(initialValue: 'https://wrong.example'),
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await endpoint.load();

    await tester.pumpWidget(
      MaterialApp(
        home: StartupPage(
          controller: auth,
          endpointController: endpoint,
        ),
      ),
    );

    expect(find.text('https://wrong.example'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startup-api-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      'https://correct.example',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pumpAndSettle();

    expect(endpoint.state.endpoint?.baseUrl, 'https://correct.example');
    expect(find.text('https://correct.example'), findsOneWidget);
  });
}

final class _FailingRestoreGateway extends FakeAuthGateway {
  @override
  Future<AuthSession?> restore() async {
    throw Exception('offline');
  }
}
