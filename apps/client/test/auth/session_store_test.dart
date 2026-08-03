import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/session_store.dart';

void main() {
  test('native store persists a stable device ID and rotates refresh token',
      () async {
    final values = MemorySessionKeyValueStore();
    var generated = 0;
    String newId() => 'device-${++generated}';
    final first = NativeSessionStore(
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
}
