import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../platform/secure_storage.dart';
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
  })  : _secureStorage = secureStorage ?? ledgerSecureStorage,
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

    final baseUrl = (config['baseUrl'] as String?)?.trim().isNotEmpty == true
        ? config['baseUrl'] as String
        : AiSettings.defaultBaseUrl;
    return AiSettings(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: (config['model'] as String?)?.trim().isNotEmpty == true
          ? config['model'] as String
          : AiSettings.defaultModel,
      autoGenerate: config['autoGenerate'] is bool
          ? config['autoGenerate'] as bool
          : true,
      provider: AiProviderKind.tryParse(config['provider'] as String?) ??
          AiProviderKind.infer(baseUrl: baseUrl),
      promptPreset: AiPromptPreset.tryParse(config['promptPreset'] as String?),
      customSystemPrompt: (config['customSystemPrompt'] as String?) ?? '',
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
      throw StateError(L10n.current.cannotSaveApiKey);
    }
    final written = await (await _preferences).setString(
      configPreferenceKey,
      jsonEncode({
        'provider': settings.provider.name,
        'baseUrl': settings.normalizedBaseUrl,
        'model': settings.model.trim().isEmpty
            ? AiSettings.defaultModel
            : settings.model.trim(),
        'autoGenerate': settings.autoGenerate,
        'promptPreset': settings.promptPreset.name,
        'customSystemPrompt': settings.customSystemPrompt,
      }),
    );
    if (!written) {
      throw StateError(L10n.current.cannotSaveModelSettings);
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
          ? (settings.presetModels.isNotEmpty
              ? settings.presetModels.first
              : AiSettings.defaultModel)
          : settings.model.trim(),
      provider: settings.provider,
      promptPreset: settings.promptPreset,
      customSystemPrompt: settings.customSystemPrompt.trim(),
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
