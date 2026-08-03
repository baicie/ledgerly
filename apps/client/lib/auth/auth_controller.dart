import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

enum AuthStatus {
  restoring,
  signedOut,
  authenticating,
  authenticated,
  failure,
}

@immutable
class AuthState {
  const AuthState._({
    required this.status,
    this.session,
    this.message,
  });

  const AuthState.restoring() : this._(status: AuthStatus.restoring);

  const AuthState.signedOut({String? message})
      : this._(status: AuthStatus.signedOut, message: message);

  const AuthState.authenticating() : this._(status: AuthStatus.authenticating);

  const AuthState.authenticated(AuthSession session)
      : this._(status: AuthStatus.authenticated, session: session);

  const AuthState.failure(String message)
      : this._(status: AuthStatus.failure, message: message);

  final AuthStatus status;
  final AuthSession? session;
  final String? message;

  bool get isBusy =>
      status == AuthStatus.restoring || status == AuthStatus.authenticating;
}

class AuthController extends ChangeNotifier {
  AuthController(this._gateway) {
    _gateway.addListener(_onGatewayChanged);
  }

  final AuthGateway _gateway;
  AuthState _state = const AuthState.restoring();

  AuthState get state => _state;

  Future<void> restore() async {
    _setState(const AuthState.restoring());
    try {
      final session = await _gateway.restore();
      _setState(
        session == null
            ? const AuthState.signedOut()
            : AuthState.authenticated(session),
      );
    } catch (error) {
      _setState(AuthState.failure(_errorMessage(error, operation: '恢复会话')));
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    _setState(const AuthState.authenticating());
    try {
      final session = await _gateway.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      _setState(AuthState.authenticated(session));
    } catch (error) {
      _setState(
        AuthState.signedOut(message: _errorMessage(error, operation: '登录')),
      );
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _setState(const AuthState.authenticating());
    try {
      final session = await _gateway.registerAndLogin(
        email: email.trim().toLowerCase(),
        password: password,
        displayName: displayName.trim(),
      );
      _setState(AuthState.authenticated(session));
    } catch (error) {
      _setState(
        AuthState.signedOut(message: _errorMessage(error, operation: '注册')),
      );
    }
  }

  Future<void> logout() async {
    try {
      await _gateway.logout();
      _setState(const AuthState.signedOut());
    } catch (_) {
      _setState(
        const AuthState.signedOut(
          message: '已清除本机登录状态，但服务器会话撤销失败。',
        ),
      );
    }
  }

  void clearMessage() {
    if (_state.status == AuthStatus.signedOut && _state.message != null) {
      _setState(const AuthState.signedOut());
    }
  }

  void _onGatewayChanged() {
    final session = _gateway.currentSession;
    if (session != null) {
      _setState(AuthState.authenticated(session));
    } else if (_state.status == AuthStatus.authenticated) {
      _setState(
        const AuthState.signedOut(
          message: '登录状态已失效，请重新登录。',
        ),
      );
    }
  }

  void _setState(AuthState value) {
    _state = value;
    notifyListeners();
  }

  String _errorMessage(Object error, {required String operation}) {
    if (error is DioException) {
      final data = error.response?.data;
      final code = data is Map ? data['code'] : null;
      return switch (code) {
        'INVALID_CREDENTIALS' => '邮箱或密码错误。',
        'EMAIL_TAKEN' => '该邮箱已注册。',
        'INVALID_EMAIL' => '请输入有效邮箱。',
        'WEAK_PASSWORD' => '密码至少 8 位。',
        _
            when error.type == DioExceptionType.connectionError ||
                error.type == DioExceptionType.connectionTimeout =>
          '无法连接服务器，请检查网络后重试。',
        _ => '$operation失败，请稍后重试。',
      };
    }
    return '$operation失败，请稍后重试。';
  }

  @override
  void dispose() {
    _gateway.removeListener(_onGatewayChanged);
    super.dispose();
  }
}
