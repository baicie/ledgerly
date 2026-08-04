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

    test('remote endpoint validation rejects empty input in every build', () {
      for (final isRelease in [false, true]) {
        expect(
          () => ApiEndpoint.resolve(
            configured: '',
            isRelease: isRelease,
            isWeb: false,
          ),
          throwsFormatException,
        );
      }
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

    test('release web rejects custom HTTPS ports for cookie isolation', () {
      expect(
        () => ApiEndpoint.resolve(
          configured: 'https://api.example:8443',
          isRelease: true,
          isWeb: true,
        ),
        throwsFormatException,
      );
    });

    test('release web accepts and normalizes an explicit port 443', () {
      final endpoint = ApiEndpoint.resolve(
        configured: 'https://api.example:443',
        isRelease: true,
        isWeb: true,
      );

      expect(endpoint.baseUrl, 'https://api.example');
    });

    test('release native accepts a custom HTTPS port', () {
      final endpoint = ApiEndpoint.resolve(
        configured: 'https://api.example:8443',
        isRelease: true,
        isWeb: false,
      );

      expect(endpoint.baseUrl, 'https://api.example:8443');
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

    test('debug accepts an explicitly configured HTTP loopback origin', () {
      final endpoint = ApiEndpoint.resolve(
        configured: 'http://127.0.0.1:8080',
        isRelease: false,
        isWeb: false,
      );

      expect(endpoint.baseUrl, 'http://127.0.0.1:8080');
    });
  });
}
