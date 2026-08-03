import 'package:flutter/foundation.dart';

class ApiEndpoint {
  const ApiEndpoint._(this.uri);

  static const _configured = String.fromEnvironment(
    'LEDGERLY_API_BASE_URL',
  );

  final Uri uri;

  String get baseUrl => uri.origin;

  factory ApiEndpoint.fromEnvironment() {
    return ApiEndpoint.resolve(
      configured: _configured,
      isRelease: kReleaseMode,
      isWeb: kIsWeb,
      webOrigin: kIsWeb ? Uri.base : null,
    );
  }

  factory ApiEndpoint.resolve({
    required String configured,
    required bool isRelease,
    required bool isWeb,
    Uri? webOrigin,
  }) {
    final value = configured.trim();
    if (value.isEmpty && isRelease) {
      throw const FormatException(
        'LEDGERLY_API_BASE_URL is required in release builds.',
      );
    }

    final candidate = value.isNotEmpty
        ? Uri.tryParse(value)
        : isWeb
            ? webOrigin
            : Uri.parse('http://127.0.0.1:8080');
    if (candidate == null ||
        !candidate.hasScheme ||
        !candidate.hasAuthority ||
        !const {'http', 'https'}.contains(candidate.scheme.toLowerCase())) {
      throw const FormatException('The API endpoint must be an HTTP(S) URL.');
    }
    if (candidate.userInfo.isNotEmpty ||
        candidate.hasQuery ||
        candidate.hasFragment ||
        (candidate.path.isNotEmpty && candidate.path != '/')) {
      throw const FormatException(
        'The API endpoint must be an origin without credentials, path, query, or fragment.',
      );
    }

    final host = candidate.host.toLowerCase();
    final isLoopback = host == 'localhost' ||
        host == '::1' ||
        host == '0.0.0.0' ||
        host.startsWith('127.');
    if (isRelease && (candidate.scheme != 'https' || isLoopback)) {
      throw const FormatException(
        'Release builds require a non-loopback HTTPS API endpoint.',
      );
    }

    return ApiEndpoint._(Uri.parse(candidate.origin));
  }
}
