import 'package:flutter/foundation.dart';

import 'api_endpoint.dart';

abstract interface class ApiEndpointStore {
  Future<String?> read();

  Future<void> write(String value);
}

enum ApiEndpointStatus { loading, needsConfiguration, ready }

@immutable
class ApiEndpointState {
  const ApiEndpointState._({
    required this.status,
    this.endpoint,
    this.message,
  });

  const ApiEndpointState.loading() : this._(status: ApiEndpointStatus.loading);

  const ApiEndpointState.needsConfiguration({String? message})
      : this._(
          status: ApiEndpointStatus.needsConfiguration,
          message: message,
        );

  const ApiEndpointState.ready(ApiEndpoint endpoint)
      : this._(status: ApiEndpointStatus.ready, endpoint: endpoint);

  final ApiEndpointStatus status;
  final ApiEndpoint? endpoint;
  final String? message;
}

class ApiEndpointController extends ChangeNotifier {
  ApiEndpointController({
    required ApiEndpointStore store,
    required String buildDefault,
    required bool isRelease,
    required bool isWeb,
    Uri? webOrigin,
  })  : _store = store,
        _buildDefault = buildDefault,
        _isRelease = isRelease,
        _isWeb = isWeb,
        _webOrigin = webOrigin;

  final ApiEndpointStore _store;
  final String _buildDefault;
  final bool _isRelease;
  final bool _isWeb;
  final Uri? _webOrigin;
  ApiEndpointState _state = const ApiEndpointState.loading();

  ApiEndpointState get state => _state;

  Future<void> load() async {
    String? persisted;
    try {
      persisted = await _store.read();
    } catch (_) {
      _setState(
        const ApiEndpointState.needsConfiguration(
          message: '无法读取已保存的 API 地址，请重新设置。',
        ),
      );
      return;
    }

    final savedValue = persisted?.trim() ?? '';
    final buildValue = _buildDefault.trim();
    if (savedValue.isEmpty && buildValue.isEmpty && _isRelease) {
      _setState(const ApiEndpointState.needsConfiguration());
      return;
    }

    try {
      final endpoint = ApiEndpoint.resolve(
        configured: savedValue.isNotEmpty ? savedValue : buildValue,
        isRelease: _isRelease,
        isWeb: _isWeb,
        webOrigin: _webOrigin,
      );
      _setState(ApiEndpointState.ready(endpoint));
    } on FormatException catch (error) {
      _setState(
        ApiEndpointState.needsConfiguration(message: error.message),
      );
    }
  }

  ApiEndpoint validate(String value) {
    return ApiEndpoint.resolve(
      configured: value,
      isRelease: _isRelease,
      isWeb: _isWeb,
      webOrigin: _webOrigin,
    );
  }

  Future<ApiEndpoint> save(String value) async {
    final endpoint = validate(value);
    await _store.write(endpoint.baseUrl);
    _setState(ApiEndpointState.ready(endpoint));
    return endpoint;
  }

  void _setState(ApiEndpointState value) {
    _state = value;
    notifyListeners();
  }
}

class MemoryApiEndpointStore implements ApiEndpointStore {
  MemoryApiEndpointStore({String? initialValue}) : value = initialValue;

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
