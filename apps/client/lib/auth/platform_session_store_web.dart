import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'session_store.dart';

SessionStore createSessionStore() {
  return CookieSessionStore(
    keyValueStore: WebLocalSessionKeyValueStore(),
    idFactory: const Uuid().v4,
  );
}

final class WebLocalSessionKeyValueStore implements SessionKeyValueStore {
  @override
  Future<void> delete(String key) async {
    web.window.localStorage.removeItem(key);
  }

  @override
  Future<String?> read(String key) async {
    return web.window.localStorage.getItem(key);
  }

  @override
  Future<void> write(String key, String value) async {
    web.window.localStorage.setItem(key, value);
  }
}
