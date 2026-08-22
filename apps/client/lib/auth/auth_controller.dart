import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'auth_repository.dart';

enum AuthStatus {
  local,
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

  const AuthState.local() : this._(status: AuthStatus.local);

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
  AuthController(AuthGateway gateway)
      : _gateway = gateway,
        _state = const AuthState.restoring() {
    gateway.addListener(_onGatewayChanged);
  }

  AuthController.local()
      : _gateway = null,
        _state = const AuthState.local();

  final AuthGateway? _gateway;
  AuthState _state;

  AuthState get state => _state;

  Future<void> restore() async {
    final gateway = _gateway;
    if (gateway == null) {
      _setState(const AuthState.local());
      return;
    }
    _setState(const AuthState.restoring());
    try {
      final session = await gateway.restore();
      _setState(
        session == null
            ? const AuthState.signedOut()
            : AuthState.authenticated(session),
      );
    } catch (error) {
      _setState(AuthState.failure(
          _errorMessage(error, L10n.current.restoreSessionFailedRetry)));
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final gateway = _requireRemoteGateway();
    _setState(const AuthState.authenticating());
    try {
      final session = await gateway.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      _setState(AuthState.authenticated(session));
    } catch (error) {
      _setState(
        AuthState.signedOut(
          message: _errorMessage(error, L10n.current.loginFailedRetry),
        ),
      );
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final gateway = _requireRemoteGateway();
    _setState(const AuthState.authenticating());
    try {
      final session = await gateway.registerAndLogin(
        email: email.trim().toLowerCase(),
        password: password,
        displayName: displayName.trim(),
      );
      _setState(AuthState.authenticated(session));
    } catch (error) {
      _setState(
        AuthState.signedOut(
          message: _errorMessage(error, L10n.current.registerFailedRetry),
        ),
      );
    }
  }

  Future<void> logout() async {
    final gateway = _gateway;
    if (gateway == null) {
      _setState(const AuthState.local());
      return;
    }
    try {
      await gateway.logout();
      _setState(const AuthState.signedOut());
    } catch (_) {
      _setState(
        AuthState.signedOut(
          message: L10n.current.logoutRemoteRevokeFailed,
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
    final session = _gateway?.currentSession;
    if (session != null) {
      _setState(AuthState.authenticated(session));
    } else if (_state.status == AuthStatus.authenticated) {
      _setState(
        AuthState.signedOut(
          message: L10n.current.sessionExpired,
        ),
      );
    }
  }

  void _setState(AuthState value) {
    _state = value;
    notifyListeners();
  }

  AuthGateway _requireRemoteGateway() {
    final gateway = _gateway;
    if (gateway == null) {
      throw StateError('Remote authentication is unavailable in local mode.');
    }
    return gateway;
  }

  String _errorMessage(Object error, String fallback) {
    final l10n = L10n.current;
    if (error is DioException) {
      final data = error.response?.data;
      final code = data is Map ? data['code'] : null;
      return switch (code) {
        'INVALID_CREDENTIALS' => l10n.invalidCredentials,
        'EMAIL_TAKEN' => l10n.emailTaken,
        'INVALID_EMAIL' => l10n.invalidEmail,
        'WEAK_PASSWORD' => l10n.weakPassword,
        _
            when error.type == DioExceptionType.connectionError ||
                error.type == DioExceptionType.connectionTimeout =>
          l10n.cannotReachServer,
        _ => fallback,
      };
    }
    return fallback;
  }

  @override
  void dispose() {
    _gateway?.removeListener(_onGatewayChanged);
    super.dispose();
  }
}
