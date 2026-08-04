typedef DeviceIdFactory = String Function();

abstract interface class SessionKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

abstract interface class SessionStore {
  bool get usesCookieSession;

  Future<String> getOrCreateDeviceId();

  Future<bool> shouldAttemptRestore();

  Future<void> markAuthenticated();

  Future<String?> readRefreshToken();

  Future<void> writeRefreshToken(String token);

  Future<void> clearAuthentication();
}

abstract base class BaseSessionStore implements SessionStore {
  BaseSessionStore({
    required String apiOrigin,
    required SessionKeyValueStore keyValueStore,
    required DeviceIdFactory idFactory,
  })  : _keyValueStore = keyValueStore,
        _idFactory = idFactory,
        _keySuffix = Uri.encodeComponent(apiOrigin);

  final SessionKeyValueStore _keyValueStore;
  final DeviceIdFactory _idFactory;
  final String _keySuffix;

  SessionKeyValueStore get keyValueStore => _keyValueStore;

  String get deviceIdKey => 'ledgerly.device_id.v2.$_keySuffix';

  String get refreshTokenKey => 'ledgerly.refresh_token.v2.$_keySuffix';

  String get webSignedOutKey => 'ledgerly.web_signed_out.v2.$_keySuffix';

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _keyValueStore.read(deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _idFactory();
    if (created.isEmpty) {
      throw StateError('Device ID generation returned an empty value.');
    }
    await _keyValueStore.write(deviceIdKey, created);
    return created;
  }
}

final class NativeSessionStore extends BaseSessionStore {
  NativeSessionStore({
    required super.apiOrigin,
    required super.keyValueStore,
    required super.idFactory,
  });

  @override
  bool get usesCookieSession => false;

  @override
  Future<bool> shouldAttemptRestore() async {
    final token = await readRefreshToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> markAuthenticated() async {}

  @override
  Future<String?> readRefreshToken() => keyValueStore.read(refreshTokenKey);

  @override
  Future<void> writeRefreshToken(String token) {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'must not be empty');
    }
    return keyValueStore.write(refreshTokenKey, token);
  }

  @override
  Future<void> clearAuthentication() => keyValueStore.delete(refreshTokenKey);
}

final class CookieSessionStore extends BaseSessionStore {
  CookieSessionStore({
    required super.apiOrigin,
    required super.keyValueStore,
    required super.idFactory,
  });

  @override
  bool get usesCookieSession => true;

  @override
  Future<bool> shouldAttemptRestore() async {
    return await keyValueStore.read(webSignedOutKey) != 'true';
  }

  @override
  Future<void> markAuthenticated() {
    return keyValueStore.delete(webSignedOutKey);
  }

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String token) async {
    throw StateError('Web refresh tokens must remain in HttpOnly cookies.');
  }

  @override
  Future<void> clearAuthentication() {
    return keyValueStore.write(webSignedOutKey, 'true');
  }
}

final class MemorySessionKeyValueStore implements SessionKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
