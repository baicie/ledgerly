import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/config/api_endpoint_controller.dart';

void main() {
  group('ApiEndpointController', () {
    test('release without a saved or embedded endpoint uses local mode',
        () async {
      final controller = releaseController(MemoryApiEndpointStore());

      await controller.load();

      expect(controller.state.status, ApiEndpointStatus.ready);
      expect(controller.state.endpoint, isNull);
      expect(controller.state.isLocal, isTrue);
    });

    test('saved endpoint takes precedence over the embedded default', () async {
      final store = MemoryApiEndpointStore(
        initialValue: 'https://saved.example',
      );
      final controller = releaseController(
        store,
        buildDefault: 'https://default.example',
      );

      await controller.load();

      expect(controller.state.status, ApiEndpointStatus.ready);
      expect(controller.state.endpoint?.baseUrl, 'https://saved.example');
    });

    test('saved endpoint is normalized and restored after restart', () async {
      final store = MemoryApiEndpointStore();
      final first = releaseController(store);
      await first.load();

      await first.save('  https://api.example/  ');

      expect(store.value, 'https://api.example');
      final restarted = releaseController(store);
      await restarted.load();
      expect(restarted.state.endpoint?.baseUrl, 'https://api.example');
    });

    test('release accepts public HTTP when HTTPS is explicitly disabled',
        () async {
      final controller = ApiEndpointController(
        store: MemoryApiEndpointStore(),
        buildDefault: '',
        isRelease: true,
        isWeb: false,
        requireHttps: false,
      );

      await controller.load();
      final endpoint = await controller.save('http://api.example:8080');

      expect(endpoint?.baseUrl, 'http://api.example:8080');
      expect(controller.state.endpoint?.baseUrl, 'http://api.example:8080');
    });

    test('saved blank endpoint overrides the embedded default with local mode',
        () async {
      final controller = releaseController(
        MemoryApiEndpointStore(initialValue: ''),
        buildDefault: 'https://default.example',
      );

      await controller.load();

      expect(controller.state.status, ApiEndpointStatus.ready);
      expect(controller.state.endpoint, isNull);
      expect(controller.state.isLocal, isTrue);
    });

    test('clearing an endpoint persists and restores local mode', () async {
      final store = MemoryApiEndpointStore(
        initialValue: 'https://api.example',
      );
      final controller = releaseController(store);
      await controller.load();

      final endpoint = await controller.save('   ');

      expect(endpoint, isNull);
      expect(store.value, '');
      expect(controller.state.isLocal, isTrue);

      final restarted = releaseController(
        store,
        buildDefault: 'https://default.example',
      );
      await restarted.load();
      expect(restarted.state.isLocal, isTrue);
      expect(restarted.state.endpoint, isNull);
    });

    test('invalid saved endpoint does not fall back to embedded default',
        () async {
      final controller = releaseController(
        MemoryApiEndpointStore(initialValue: 'http://insecure.example'),
        buildDefault: 'https://default.example',
      );

      await controller.load();

      expect(controller.state.status, ApiEndpointStatus.needsConfiguration);
      expect(controller.state.endpoint, isNull);
      expect(controller.state.message, isNotNull);
    });

    test('failed persistence leaves the active endpoint unchanged', () async {
      final store = _FailingWriteEndpointStore(
        initialValue: 'https://old.example',
      );
      final controller = releaseController(store);
      await controller.load();

      await expectLater(
        controller.save('https://new.example'),
        throwsStateError,
      );

      expect(controller.state.endpoint?.baseUrl, 'https://old.example');
      expect(store.value, 'https://old.example');
    });

    test('debug also uses local mode when no endpoint is configured', () async {
      final controller = ApiEndpointController(
        store: MemoryApiEndpointStore(),
        buildDefault: '',
        isRelease: false,
        isWeb: false,
      );

      await controller.load();

      expect(controller.state.status, ApiEndpointStatus.ready);
      expect(controller.state.endpoint, isNull);
      expect(controller.state.isLocal, isTrue);
    });
  });
}

ApiEndpointController releaseController(
  ApiEndpointStore store, {
  String buildDefault = '',
}) {
  return ApiEndpointController(
    store: store,
    buildDefault: buildDefault,
    isRelease: true,
    isWeb: false,
  );
}

final class _FailingWriteEndpointStore extends MemoryApiEndpointStore {
  _FailingWriteEndpointStore({required super.initialValue});

  @override
  Future<void> write(String value) async {
    throw StateError('preferences unavailable');
  }
}
