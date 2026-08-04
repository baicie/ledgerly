import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/config/api_endpoint_controller.dart';
import 'package:ledgerly_client/main.dart';
import 'package:ledgerly_client/presentation/pages/api_endpoint_setup_page.dart';

void main() {
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

  testWidgets('first-run setup rejects insecure release URL and saves HTTPS',
      (tester) async {
    final store = MemoryApiEndpointStore();
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
      'https://api.example/',
    );
    await tester.tap(find.byKey(const Key('api-endpoint-save')));
    await tester.pumpAndSettle();

    expect(store.value, 'https://api.example');
    expect(controller.state.status, ApiEndpointStatus.ready);
  });
}
