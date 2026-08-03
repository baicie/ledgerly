import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/api_endpoint.dart';
import 'dio_platform.dart';
import 'session_store.dart';

@immutable
class AuthSession {
  const AuthSession({required this.bookId, required this.plan});

  final String bookId;
  final String plan;
}

abstract interface class AuthGateway implements Listenable {
  AuthSession? get currentSession;

  Future<AuthSession?> restore();

  Future<AuthSession> login({
    required String email,
    required String password,
  });

  Future<AuthSession> registerAndLogin({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> logout();
}

class AuthRepository extends ChangeNotifier implements AuthGateway {
  AuthRepository({
    required ApiEndpoint endpoint,
    required SessionStore sessionStore,
    Dio? authDio,
    Dio? authenticatedDio,
  })  : _sessionStore = sessionStore,
        _authDio = authDio ?? Dio(),
        _authenticatedDio = authenticatedDio ?? Dio() {
    final options = BaseOptions(
      baseUrl: endpoint.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
    );
    _authDio.options = options;
    _authenticatedDio.options = options.copyWith();
    configureDioForPlatform(_authDio);
    configureDioForPlatform(_authenticatedDio);
    _authenticatedDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _authorize,
        onError: _refreshAndRetry,
      ),
    );
  }

  static const _retriedKey = 'ledgerly.auth.retried';

  final SessionStore _sessionStore;
  final Dio _authDio;
  final Dio _authenticatedDio;

  String? _accessToken;
  AuthSession? _currentSession;
  Future<AuthSession>? _refreshing;

  @override
  AuthSession? get currentSession => _currentSession;

  Dio get authenticatedClient => _authenticatedDio;

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _authDio.post<void>(
      '/v1/auth/register',
      data: {
        'email': email,
        'password': password,
        'displayName': displayName,
      },
    );
  }

  @override
  Future<AuthSession> registerAndLogin({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await register(email: email, password: password, displayName: displayName);
    return login(email: email, password: password);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final deviceId = await _sessionStore.getOrCreateDeviceId();
    final response = await _authDio.post<Map<String, dynamic>>(
      '/v1/auth/login',
      data: {
        'email': email,
        'password': password,
        'deviceId': deviceId,
        if (_sessionStore.usesCookieSession) 'sessionMode': 'cookie',
      },
    );
    return _acceptTokens(response.data);
  }

  @override
  Future<AuthSession?> restore() async {
    if (!_sessionStore.usesCookieSession &&
        await _sessionStore.readRefreshToken() == null) {
      return null;
    }
    try {
      return await _performRefresh();
    } on DioException catch (error) {
      if (error.response?.statusCode case 400 || 401) {
        await _clearLocalAuthentication();
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    try {
      if (_currentSession != null) {
        await _authenticatedDio.post<void>('/v1/auth/logout');
      }
    } finally {
      await _clearLocalAuthentication();
    }
  }

  void _authorize(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final token = _accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _refreshAndRetry(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        request.extra[_retriedKey] == true) {
      handler.next(error);
      return;
    }

    try {
      await _refreshOnce();
      request.extra[_retriedKey] = true;
      request.headers['Authorization'] = 'Bearer $_accessToken';
      final response = await _authenticatedDio.fetch<dynamic>(request);
      handler.resolve(response);
    } catch (_) {
      handler.next(error);
    }
  }

  Future<AuthSession> _refreshOnce() {
    final active = _refreshing;
    if (active != null) {
      return active;
    }
    final created = _runRefresh();
    _refreshing = created;
    return created;
  }

  Future<AuthSession> _runRefresh() async {
    try {
      return await _performRefresh();
    } catch (_) {
      await _clearLocalAuthentication();
      rethrow;
    } finally {
      _refreshing = null;
    }
  }

  Future<AuthSession> _performRefresh() async {
    final data = <String, dynamic>{};
    if (_sessionStore.usesCookieSession) {
      data['sessionMode'] = 'cookie';
    } else {
      final refreshToken = await _sessionStore.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const NoSessionException();
      }
      data['refreshToken'] = refreshToken;
    }
    final response = await _authDio.post<Map<String, dynamic>>(
      '/v1/auth/refresh',
      data: data,
    );
    return _acceptTokens(response.data);
  }

  Future<AuthSession> _acceptTokens(Map<String, dynamic>? body) async {
    final accessToken = body?['accessToken'];
    final bookId = body?['bookId'];
    final plan = body?['plan'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        bookId is! String ||
        bookId.isEmpty) {
      throw const FormatException('Invalid authentication response.');
    }

    if (_sessionStore.usesCookieSession) {
      if (body?.containsKey('refreshToken') == true) {
        throw const FormatException(
          'Cookie authentication responses must not expose refreshToken.',
        );
      }
    } else {
      final refreshToken = body?['refreshToken'];
      if (refreshToken is! String || refreshToken.isEmpty) {
        throw const FormatException(
            'Authentication response has no refreshToken.');
      }
      await _sessionStore.writeRefreshToken(refreshToken);
    }

    _accessToken = accessToken;
    _currentSession = AuthSession(
      bookId: bookId,
      plan: plan is String && plan.isNotEmpty ? plan : 'free',
    );
    notifyListeners();
    return _currentSession!;
  }

  Future<void> _clearLocalAuthentication() async {
    final changed = _accessToken != null || _currentSession != null;
    _accessToken = null;
    _currentSession = null;
    await _sessionStore.clearAuthentication();
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authDio.close();
    _authenticatedDio.close();
    super.dispose();
  }
}

class NoSessionException implements Exception {
  const NoSessionException();
}
