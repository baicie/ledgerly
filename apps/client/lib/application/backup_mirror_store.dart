import 'package:shared_preferences/shared_preferences.dart';

class BackupMirrorStore {
  BackupMirrorStore({Future<SharedPreferences> Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String preferencesKey = 'ledgerly.backup.externalDirectory';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<String?> read() async {
    final prefs = await _prefsLoader();
    final value = prefs.getString(preferencesKey);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  Future<void> save(String directory) async {
    final prefs = await _prefsLoader();
    await prefs.setString(preferencesKey, directory);
  }

  Future<void> clear() async {
    final prefs = await _prefsLoader();
    await prefs.remove(preferencesKey);
  }
}
