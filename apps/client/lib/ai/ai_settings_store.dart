import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';

abstract interface class AiSettingsStore {
  Future<AiSettings> read();

  Future<void> write(AiSettings settings);
}

class MemoryAiSettingsStore implements AiSettingsStore {
  MemoryAiSettingsStore({AiSettings? initial})
    : value = initial ?? AiSettings.unset;

  AiSettings value;

  @override
  Future<AiSettings> read() async => value;

  @override
  Future<void> write(AiSettings settings) async {
    value = settings;
  }
}

class PlatformAiSettingsStore implements AiSettingsStore {
  PlatformAiSettingsStore({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences>? preferences,
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(migrateWithBackup: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _preferences = preferences ?? SharedPreferences.getInstance();

  static const apiKeyStorageKey = 'ledgerly.ai.api_key.v1';
  static const configPreferenceKey = 'ledgerly.ai.config.v1';

  final FlutterSecureStorage _secureStorage;
  final Future<SharedPreferences> _preferences;

  @override
  Future<AiSettings> read() async {
    var apiKey = '';
    try {
      apiKey = (await _secureStorage.read(key: apiKeyStorageKey)) ?? '';
    } catch (_) {
      apiKey = '';
    }

    Map<String, dynamic> config = const {};
    try {
      final raw = (await _preferences).getString(configPreferenceKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          config = decoded;
        } else if (decoded is Map) {
          config = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}

    return AiSettings(
      apiKey: apiKey,
      baseUrl: (config['baseUrl'] as String?)?.trim().isNotEmpty == true
          ? config['baseUrl'] as String
          : AiSettings.defaultBaseUrl,
      model: (config['model'] as String?)?.trim().isNotEmpty == true
          ? config['model'] as String
          : AiSettings.defaultModel,
      autoGenerate: config['autoGenerate'] is bool
          ? config['autoGenerate'] as bool
          : true,
    );
  }

  @override
  Future<void> write(AiSettings settings) async {
    try {
      final key = settings.apiKey.trim();
      if (key.isEmpty) {
        await _secureStorage.delete(key: apiKeyStorageKey);
      } else {
        await _secureStorage.write(key: apiKeyStorageKey, value: key);
      }
    } catch (_) {
      throw StateError('无法保存 API Key。');
    }
    final written = await (await _preferences).setString(
      configPreferenceKey,
      jsonEncode({
        'baseUrl': settings.normalizedBaseUrl,
        'model': settings.model.trim().isEmpty
            ? AiSettings.defaultModel
            : settings.model.trim(),
        'autoGenerate': settings.autoGenerate,
      }),
    );
    if (!written) {
      throw StateError('无法保存模型设置。');
    }
  }
}

AiSettingsStore createPlatformAiSettingsStore() => PlatformAiSettingsStore();

class AiSettingsController extends ChangeNotifier {
  AiSettingsController({required AiSettingsStore store}) : _store = store;

  final AiSettingsStore _store;
  AiSettings _settings = AiSettings.unset;
  var _loaded = false;
  var _disposed = false;

  AiSettings get settings => _settings;

  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      _settings = await _store.read();
    } catch (_) {
      _settings = AiSettings.unset;
    }
    if (_disposed) return;
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(AiSettings settings) async {
    final normalized = settings.copyWith(
      apiKey: settings.apiKey.trim(),
      baseUrl: settings.normalizedBaseUrl,
      model: settings.model.trim().isEmpty
          ? AiSettings.defaultModel
          : settings.model.trim(),
    );
    await _store.write(normalized);
    if (_disposed) return;
    _settings = normalized;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
