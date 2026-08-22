import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/config/api_endpoint_controller.dart';
import 'package:ledgerly_client/l10n/l10n.dart';
import 'package:ledgerly_client/main.dart';
import 'package:ledgerly_client/presentation/pages/api_endpoint_setup_page.dart';
import 'package:ledgerly_client/presentation/pages/startup_page.dart';

import '../support/fake_auth_gateway.dart';

void main() {
  tearDown(() {
    L10n.locale = const Locale('zh');
  });

  testWidgets('invalid endpoint recovery fits a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ApiEndpointController(
      store: MemoryApiEndpointStore(
        initialValue: 'http://insecure.example',
      ),
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ApiEndpointSetupPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('API 服务配置'), findsOneWidget);
    expect(find.text('地址选填，留空时仅在本机存储'), findsOneWidget);
    expect(find.byKey(const Key('api-endpoint-input')), findsOneWidget);
    expect(find.byKey(const Key('api-endpoint-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release bootstrap mounts the local app when no endpoint exists',
      (tester) async {
    final controller = ApiEndpointController(
      store: MemoryApiEndpointStore(),
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );

    await tester.pumpWidget(
      LedgerlyBootstrap(
        controller: controller,
        application: const MaterialApp(
          home: SizedBox(key: Key('local-application')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.status, ApiEndpointStatus.ready);
    expect(controller.state.isLocal, isTrue);
    expect(find.byType(ApiEndpointSetupPage), findsNothing);
    expect(find.byKey(const Key('local-application')), findsOneWidget);
  });

  testWidgets('recovery accepts a blank endpoint and enters local mode',
      (tester) async {
    final store = MemoryApiEndpointStore(
      initialValue: 'http://insecure.example',
    );
    final controller = ApiEndpointController(
      store: store,
      buildDefault: '',
      isRelease: true,
      isWeb: false,
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ApiEndpointSetupPage(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pumpAndSettle();

    expect(store.value, '');
    expect(controller.state.isLocal, isTrue);
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
    await tester.pump();

    expect(find.text('API 服务配置'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('api-endpoint-input')),
      'http://api.example',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pump();

    expect(find.text('请使用 HTTPS；原生客户端也支持局域网 IP 地址'), findsOneWidget);
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
