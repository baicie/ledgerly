import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/presentation/pages/auth_page.dart';

import '../support/fake_auth_gateway.dart';

void main() {
  testWidgets('login form validates required fields', (tester) async {
    final controller = AuthController(FakeAuthGateway());
    addTearDown(controller.dispose);
    await controller.restore();

    await tester.pumpWidget(
      MaterialApp(home: AuthPage(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();

    expect(find.text('请输入有效邮箱'), findsOneWidget);
    expect(find.text('密码至少 8 位'), findsOneWidget);
  });

  testWidgets('registration submits normalized account details',
      (tester) async {
    final gateway = FakeAuthGateway();
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);
    await controller.restore();

    await tester.pumpWidget(
      MaterialApp(home: AuthPage(controller: controller)),
    );
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      ' New@Example.COM ',
    );
    await tester.enterText(
      find.byKey(const Key('auth-display-name')),
      ' New Person ',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(gateway.registerEmail, 'new@example.com');
    expect(gateway.registerDisplayName, 'New Person');
    expect(controller.state.status, AuthStatus.authenticated);
  });

  testWidgets('login failure is visible and password remains hidden',
      (tester) async {
    final gateway = FakeAuthGateway()..loginError = Exception('offline');
    final controller = AuthController(gateway);
    addTearDown(controller.dispose);
    await controller.restore();

    await tester.pumpWidget(
      MaterialApp(home: AuthPage(controller: controller)),
    );
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text('登录失败，请稍后重试。'), findsOneWidget);
    final password = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('auth-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(password.obscureText, isTrue);
  });
}
