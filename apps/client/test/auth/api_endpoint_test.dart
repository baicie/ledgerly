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

    test('release native accepts public HTTP when HTTPS is not required', () {
      final endpoint = ApiEndpoint.resolve(
        configured: 'http://api.ledgerly.example:8080',
        isRelease: true,
        isWeb: false,
        requireHttps: false,
      );

      expect(endpoint.baseUrl, 'http://api.ledgerly.example:8080');
    });

    test('release Web still rejects HTTP when HTTPS is not required', () {
      expect(
        () => ApiEndpoint.resolve(
          configured: 'http://api.ledgerly.example:8080',
          isRelease: true,
          isWeb: true,
          requireHttps: false,
        ),
        throwsFormatException,
      );
    });

    test('release still rejects loopback HTTP when HTTPS is not required', () {
      expect(
        () => ApiEndpoint.resolve(
          configured: 'http://127.0.0.1:8080',
          isRelease: true,
          isWeb: false,
          requireHttps: false,
        ),
        throwsFormatException,
      );
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

    test('release native accepts a private network HTTP address', () {
      final endpoint = ApiEndpoint.resolve(
        configured: 'http://192.168.1.24:8080',
        isRelease: true,
        isWeb: false,
      );

      expect(endpoint.baseUrl, 'http://192.168.1.24:8080');
    });

    test('release native accepts private and link-local address ranges', () {
      for (final value in [
        'http://10.0.0.1:8080',
        'http://172.16.0.1:8080',
        'http://172.31.255.254:8080',
        'http://192.168.255.254:8080',
        'http://169.254.1.1:8080',
        'http://[fd00::1]:8080',
        'http://[fe80::1]:8080',
      ]) {
        expect(
          ApiEndpoint.resolve(
            configured: value,
            isRelease: true,
            isWeb: false,
          ).uri.scheme,
          'http',
          reason: value,
        );
      }
    });

    test('release rejects HTTP just outside private address ranges', () {
      for (final value in [
        'http://9.255.255.255:8080',
        'http://11.0.0.0:8080',
        'http://172.15.255.255:8080',
        'http://172.32.0.0:8080',
        'http://192.167.255.255:8080',
        'http://192.169.0.0:8080',
        'http://169.253.255.255:8080',
        'http://169.255.0.0:8080',
        'http://[fbff::1]:8080',
        'http://[fec0::1]:8080',
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

    test('release web rejects private network HTTP addresses', () {
      expect(
        () => ApiEndpoint.resolve(
          configured: 'http://192.168.1.24:8080',
          isRelease: true,
          isWeb: true,
        ),
        throwsFormatException,
      );
    });

    test('resource URLs use the same release transport policy', () {
      expect(
        ApiEndpoint.validateResourceUrl(
          'https://storage.example/upload?id=one',
          isRelease: true,
          isWeb: false,
        ).path,
        '/upload',
      );
      expect(
        ApiEndpoint.validateResourceUrl(
          'http://192.168.1.24:8080/upload?id=one',
          isRelease: true,
          isWeb: false,
        ).host,
        '192.168.1.24',
      );
      expect(
        () => ApiEndpoint.validateResourceUrl(
          'http://storage.example/upload?id=one',
          isRelease: true,
          isWeb: false,
        ),
        throwsFormatException,
      );
    });

    test('resource URLs accept public HTTP when HTTPS is not required', () {
      final uri = ApiEndpoint.validateResourceUrl(
        'http://storage.example/upload?id=one',
        isRelease: true,
        isWeb: false,
        requireHttps: false,
      );

      expect(uri.scheme, 'http');
      expect(uri.host, 'storage.example');
    });

    test('release native adds HTTP to a private IPv4 address', () {
      final endpoint = ApiEndpoint.resolve(
        configured: '192.168.1.24:8080',
        isRelease: true,
        isWeb: false,
      );

      expect(endpoint.baseUrl, 'http://192.168.1.24:8080');
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
