import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/config/api_endpoint.dart';

void main() {
  group('ApiEndpoint', () {
    test('accepts and normalizes an explicit HTTPS origin', () {
      final endpoint = ApiEndpoint.resolve(
        configured: 'https://api.ledgerly.example/',
        isRelease: true,
        isWeb: false,
      );

      expect(endpoint.baseUrl, 'https://api.ledgerly.example');
    });

    test('release requires an explicit endpoint', () {
      expect(
        () => ApiEndpoint.resolve(
          configured: '',
          isRelease: true,
          isWeb: false,
        ),
        throwsFormatException,
      );
    });

    test('release rejects HTTP and loopback endpoints', () {
      for (final value in [
        'http://api.ledgerly.example',
        'https://0.0.0.0',
        'https://127.0.0.1:8080',
        'https://127.1',
        'https://0x7f000001',
        'https://localhost:8080',
        'https://localhost.',
        'https://app.localhost',
        'https://2130706433',
        'https://0177.0.0.1',
        'https://[::]',
        'https://[::1]',
        'https://[0:0:0:0:0:0:0:1]',
        'https://[::ffff:127.0.0.1]',
        'https://[::ffff:7f00:1]',
      ]) {
        expect(
          () => ApiEndpoint.resolve(
            configured: value,
            isRelease: true,
            isWeb: false,
          ),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('rejects credentials, query, fragment, and non-root path', () {
      for (final value in [
        'https://user:pass@api.example',
        'https://api.example/v1',
        'https://api.example?tenant=one',
        'https://api.example#fragment',
      ]) {
        expect(
          () => ApiEndpoint.resolve(
            configured: value,
            isRelease: false,
            isWeb: false,
          ),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('debug web defaults to the current HTTP origin', () {
      final endpoint = ApiEndpoint.resolve(
        configured: '',
        isRelease: false,
        isWeb: true,
        webOrigin: Uri.parse('http://localhost:5173'),
      );

      expect(endpoint.baseUrl, 'http://localhost:5173');
    });

    test('debug native defaults to the local API', () {
      final endpoint = ApiEndpoint.resolve(
        configured: '',
        isRelease: false,
        isWeb: false,
      );

      expect(endpoint.baseUrl, 'http://127.0.0.1:8080');
    });
  });
}
