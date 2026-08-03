import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/routing/app_router.dart';

void main() {
  test('route guard covers restore, signed-out, and authenticated states', () {
    expect(
      authRedirect(const AuthState.restoring(), '/feed'),
      '/startup',
    );
    expect(
      authRedirect(const AuthState.signedOut(), '/settings'),
      '/auth',
    );
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
}
