import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';

import '../support/fake_auth_gateway.dart';

void main() {
  test('startup restore moves to signed out when no session exists', () async {
    final gateway = FakeAuthGateway();
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.status, AuthStatus.signedOut);
    expect(controller.state.session, isNull);
  });

  test('startup restore authenticates and repository invalidation signs out',
      () async {
    final gateway = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'plus');
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);

    await controller.restore();
    expect(controller.state.status, AuthStatus.authenticated);
    expect(controller.state.session?.plan, 'plus');

    gateway.invalidate();
    expect(controller.state.status, AuthStatus.signedOut);
    expect(controller.state.message, '登录状态已失效，请重新登录。');
  });

  test('login normalizes email and exposes authenticated session', () async {
    final gateway = FakeAuthGateway()
      ..loginResult = const AuthSession(bookId: 'book-2', plan: 'free');
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);

    await controller.login(
      email: ' Person@Example.COM ',
      password: 'password123',
    );

    expect(gateway.loginEmail, 'person@example.com');
    expect(controller.state.status, AuthStatus.authenticated);
    expect(controller.state.session?.bookId, 'book-2');
  });

  test('registration trims identity fields', () async {
    final gateway = FakeAuthGateway()
      ..registerResult = const AuthSession(bookId: 'book-3', plan: 'free');
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);

    await controller.register(
      email: ' NEW@Example.COM ',
      password: 'password123',
      displayName: '  New Person  ',
    );

    expect(gateway.registerEmail, 'new@example.com');
    expect(gateway.registerDisplayName, 'New Person');
    expect(controller.state.status, AuthStatus.authenticated);
  });

  test('logout transitions to signed out', () async {
    final gateway = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'book-1', plan: 'free');
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);
    await controller.restore();

    await controller.logout();

    expect(gateway.logoutCalled, isTrue);
    expect(controller.state.status, AuthStatus.signedOut);
  });
}
