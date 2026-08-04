import 'session_store.dart';
import 'platform_session_store_native.dart'
    if (dart.library.js_interop) 'platform_session_store_web.dart' as platform;

SessionStore createPlatformSessionStore(String apiOrigin) =>
    platform.createSessionStore(apiOrigin);
