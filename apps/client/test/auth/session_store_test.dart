import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/session_store.dart';

void main() {
  test('native store persists a stable device ID and rotates refresh token',
      () async {
    final values = MemorySessionKeyValueStore();
    var generated = 0;
    String newId() => 'device-${++generated}';
    final first = NativeSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: newId,
    );

    expect(await first.getOrCreateDeviceId(), 'device-1');
    expect(await first.getOrCreateDeviceId(), 'device-1');
    await first.writeRefreshToken('refresh-one');
    expect(await first.readRefreshToken(), 'refresh-one');
    await first.writeRefreshToken('refresh-two');
    expect(await first.readRefreshToken(), 'refresh-two');

    final afterRestart = NativeSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: newId,
    );
    expect(await afterRestart.getOrCreateDeviceId(), 'device-1');
    expect(await afterRestart.readRefreshToken(), 'refresh-two');

    await afterRestart.clearAuthentication();
    expect(await afterRestart.readRefreshToken(), isNull);
    expect(await afterRestart.getOrCreateDeviceId(), 'device-1');
  });

  test('cookie store persists only non-secret device identity', () async {
    final values = MemorySessionKeyValueStore();
    final store = CookieSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: () => 'web-device',
    );

    expect(store.usesCookieSession, isTrue);
    expect(await store.getOrCreateDeviceId(), 'web-device');
    expect(await store.readRefreshToken(), isNull);
    await expectLater(
      store.writeRefreshToken('must-not-be-written'),
      throwsStateError,
    );
    expect(values.values.values, isNot(contains('must-not-be-written')));

    expect(await store.shouldAttemptRestore(), isTrue);
    await store.clearAuthentication();
    expect(await store.shouldAttemptRestore(), isFalse);
    await store.markAuthenticated();
    expect(await store.shouldAttemptRestore(), isTrue);
  });

  test('native credentials and device identity are isolated by API origin',
      () async {
    final values = MemorySessionKeyValueStore();
    var generated = 0;
    String newId() => 'device-${++generated}';
    final first = NativeSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: newId,
    );
    final second = NativeSessionStore(
      apiOrigin: 'https://two.example',
      keyValueStore: values,
      idFactory: newId,
    );

    await first.writeRefreshToken('refresh-one');

    expect(await first.getOrCreateDeviceId(), 'device-1');
    expect(await second.getOrCreateDeviceId(), 'device-2');
    expect(await second.readRefreshToken(), isNull);
    await second.writeRefreshToken('refresh-two');
    expect(await first.readRefreshToken(), 'refresh-one');
    expect(await second.readRefreshToken(), 'refresh-two');
  });

  test('web signed-out markers are isolated by API origin', () async {
    final values = MemorySessionKeyValueStore();
    final first = CookieSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: () => 'device-one',
    );
    final second = CookieSessionStore(
      apiOrigin: 'https://two.example',
      keyValueStore: values,
      idFactory: () => 'device-two',
    );

    await first.clearAuthentication();

    expect(await first.shouldAttemptRestore(), isFalse);
    expect(await second.shouldAttemptRestore(), isTrue);
  });

  test('legacy unscoped session values are ignored', () async {
    final values = MemorySessionKeyValueStore()
      ..values.addAll({
        'ledgerly.device_id.v1': 'legacy-device',
        'ledgerly.refresh_token.v1': 'legacy-refresh',
        'ledgerly.web_signed_out.v1': 'true',
      });
    final native = NativeSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: () => 'scoped-device',
    );
    final web = CookieSessionStore(
      apiOrigin: 'https://one.example',
      keyValueStore: values,
      idFactory: () => 'scoped-web-device',
    );

    expect(await native.getOrCreateDeviceId(), 'scoped-device');
    expect(await native.readRefreshToken(), isNull);
    expect(await web.shouldAttemptRestore(), isTrue);
  });
}
