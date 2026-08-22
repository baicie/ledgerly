import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'api_endpoint.dart';
import 'api_endpoint_messages.dart';

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

  const ApiEndpointState.local() : this._(status: ApiEndpointStatus.ready);

  const ApiEndpointState.ready(ApiEndpoint endpoint)
      : this._(status: ApiEndpointStatus.ready, endpoint: endpoint);

  final ApiEndpointStatus status;
  final ApiEndpoint? endpoint;
  final String? message;

  bool get isLocal => status == ApiEndpointStatus.ready && endpoint == null;
}

class ApiEndpointController extends ChangeNotifier {
  ApiEndpointController({
    required ApiEndpointStore store,
    required String buildDefault,
    required bool isRelease,
    required bool isWeb,
    bool requireHttps = ApiEndpoint.requireHttps,
  })  : _store = store,
        _buildDefault = buildDefault,
        _isRelease = isRelease,
        _isWeb = isWeb,
        _requireHttps = requireHttps;

  final ApiEndpointStore _store;
  final String _buildDefault;
  final bool _isRelease;
  final bool _isWeb;
  final bool _requireHttps;
  ApiEndpointState _state = const ApiEndpointState.loading();

  ApiEndpointState get state => _state;

  Future<void> load() async {
    String? persisted;
    try {
      persisted = await _store.read();
    } catch (_) {
      _setState(
        ApiEndpointState.needsConfiguration(
          message: L10n.current.cannotReadSavedApi,
        ),
      );
      return;
    }

    final savedValue = persisted?.trim();
    final buildValue = _buildDefault.trim();
    final configured = persisted == null ? buildValue : savedValue!;
    if (configured.isEmpty) {
      _setState(const ApiEndpointState.local());
      return;
    }

    try {
      final endpoint = ApiEndpoint.resolve(
        configured: configured,
        isRelease: _isRelease,
        isWeb: _isWeb,
        requireHttps: _requireHttps,
      );
      _setState(ApiEndpointState.ready(endpoint));
    } on FormatException catch (error) {
      _setState(
        ApiEndpointState.needsConfiguration(
          message: apiEndpointErrorText(error),
        ),
      );
    }
  }

  ApiEndpoint? validate(String value) {
    if (value.trim().isEmpty) return null;
    return ApiEndpoint.resolve(
      configured: value,
      isRelease: _isRelease,
      isWeb: _isWeb,
      requireHttps: _requireHttps,
    );
  }

  Future<ApiEndpoint?> save(String value) async {
    final endpoint = validate(value);
    await _store.write(endpoint?.baseUrl ?? '');
    _setState(
      endpoint == null
          ? const ApiEndpointState.local()
          : ApiEndpointState.ready(endpoint),
    );
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
