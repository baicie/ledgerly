import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/routing/app_router.dart';

void main() {
  test('route guard covers restore, signed-out, and authenticated states', () {
    final restoring = authRedirect(const AuthState.restoring(), '/feed');
    expect(Uri.parse(restoring!).path, '/startup');
    expect(Uri.parse(restoring).queryParameters['from'], '/feed');

    final signedOut = authRedirect(const AuthState.signedOut(), '/settings');
    expect(Uri.parse(signedOut!).path, '/auth');
    expect(Uri.parse(signedOut).queryParameters['from'], '/settings');
    expect(
      authRedirect(const AuthState.signedOut(), '/auth'),
      isNull,
    );
    expect(
      authRedirect(
        const AuthState.authenticated(
          AuthSession(bookId: 'book-1', plan: 'free'),
        ),
        '/auth',
      ),
      '/feed',
    );
    expect(
      authRedirect(
        const AuthState.authenticated(
          AuthSession(bookId: 'book-1', plan: 'free'),
        ),
        '/reports',
      ),
      isNull,
    );
  });

  test('session restore returns to the originally requested route', () {
    final startup = authRedirect(const AuthState.restoring(), '/settings');

    expect(startup, isNotNull);
    expect(Uri.parse(startup!).path, '/startup');
    expect(Uri.parse(startup).queryParameters['from'], '/settings');
    expect(
      authRedirect(
        const AuthState.authenticated(
          AuthSession(bookId: 'book-1', plan: 'free'),
        ),
        startup,
      ),
      '/settings',
    );
  });

  test('signed-out deep link survives startup and login', () {
    final startup = authRedirect(const AuthState.restoring(), '/reports')!;
    final auth = authRedirect(const AuthState.signedOut(), startup)!;

    expect(Uri.parse(auth).path, '/auth');
    expect(Uri.parse(auth).queryParameters['from'], '/reports');
    expect(
      authRedirect(
        const AuthState.authenticated(
          AuthSession(bookId: 'book-1', plan: 'free'),
        ),
        auth,
      ),
      '/reports',
    );
  });

  test('authenticated redirect rejects an external return location', () {
    expect(
      authRedirect(
        const AuthState.authenticated(
          AuthSession(bookId: 'book-1', plan: 'free'),
        ),
        '/auth?from=https%3A%2F%2Fevil.example',
      ),
      '/feed',
    );
  });
}
