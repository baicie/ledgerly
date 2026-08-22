import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../platform/secure_storage.dart';
import 'session_store.dart';

SessionStore createSessionStore(String apiOrigin) {
  return NativeSessionStore(
    apiOrigin: apiOrigin,
    keyValueStore: FlutterSecureSessionKeyValueStore(),
    idFactory: const Uuid().v4,
  );
}

final class FlutterSecureSessionKeyValueStore implements SessionKeyValueStore {
  FlutterSecureSessionKeyValueStore({FlutterSecureStorage? storage})
      : _storage = storage ?? ledgerSecureStorage;

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}
