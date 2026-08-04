import 'package:shared_preferences/shared_preferences.dart';

import 'api_endpoint_controller.dart';

ApiEndpointStore createPlatformApiEndpointStore() {
  return SharedPreferencesApiEndpointStore();
}

final class SharedPreferencesApiEndpointStore implements ApiEndpointStore {
  SharedPreferencesApiEndpointStore({Future<SharedPreferences>? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _key = 'ledgerly.api_endpoint.v1';

  final Future<SharedPreferences> _preferences;

  @override
  Future<String?> read() async {
    return (await _preferences).getString(_key);
  }

  @override
  Future<void> write(String value) async {
    final written = await (await _preferences).setString(_key, value);
    if (!written) {
      throw StateError('Unable to persist the API endpoint.');
    }
  }
}
