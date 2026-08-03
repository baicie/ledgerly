import 'package:flutter/foundation.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';

class FakeAuthGateway extends ChangeNotifier implements AuthGateway {
  AuthSession? restoreResult;
  AuthSession? loginResult;
  AuthSession? registerResult;
  Object? loginError;
  bool logoutCalled = false;
  String? loginEmail;
  String? registerEmail;
  String? registerDisplayName;
  AuthSession? _currentSession;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  Future<AuthSession?> restore() async {
    _currentSession = restoreResult;
    return _currentSession;
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    loginEmail = email;
    if (loginError case final error?) throw error;
    _currentSession =
        loginResult ?? const AuthSession(bookId: 'login-book', plan: 'free');
    notifyListeners();
    return _currentSession!;
  }

  @override
  Future<AuthSession> registerAndLogin({
    required String email,
    required String password,
    required String displayName,
  }) async {
    registerEmail = email;
    registerDisplayName = displayName;
    _currentSession = registerResult ??
        const AuthSession(bookId: 'register-book', plan: 'free');
    notifyListeners();
    return _currentSession!;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
    _currentSession = null;
    notifyListeners();
  }

  void invalidate() {
    _currentSession = null;
    notifyListeners();
  }
}
