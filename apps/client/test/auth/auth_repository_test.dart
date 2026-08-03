import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/auth/session_store.dart';
import 'package:ledgerly_client/config/api_endpoint.dart';

void main() {
  late MemorySessionKeyValueStore values;
  late NativeSessionStore store;
  late CallbackAdapter authAdapter;
  late CallbackAdapter resourceAdapter;
  late Dio authDio;
  late Dio resourceDio;

  setUp(() {
    values = MemorySessionKeyValueStore();
    store = NativeSessionStore(
      keyValueStore: values,
      idFactory: () => 'stable-device',
    );
    authAdapter = CallbackAdapter();
    resourceAdapter = CallbackAdapter();
    authDio = Dio()..httpClientAdapter = authAdapter;
    resourceDio = Dio()..httpClientAdapter = resourceAdapter;
  });

  AuthRepository repository({SessionStore? sessionStore}) {
    return AuthRepository(
      endpoint: ApiEndpoint.resolve(
        configured: 'http://127.0.0.1:8080',
        isRelease: false,
        isWeb: false,
      ),
      sessionStore: sessionStore ?? store,
      authDio: authDio,
      authenticatedDio: resourceDio,
    );
  }

  test('login keeps access in memory and refresh in native secure store',
      () async {
    authAdapter.handler = (request) async {
      expect(request.path, '/v1/auth/login');
      expect(request.data['deviceId'], 'stable-device');
      return jsonResponse(200, tokenBody('access-one', 'refresh-one'));
    };
    resourceAdapter.handler = (request) async {
      expect(request.headers['Authorization'], 'Bearer access-one');
      return jsonResponse(200, {'ok': true});
    };
    final repo = repository();

    final session = await repo.login(
      email: 'person@example.com',
      password: 'password123',
    );

    expect(session.bookId, 'book-1');
    expect(await store.readRefreshToken(), 'refresh-one');
    expect(values.values.values, isNot(contains('access-one')));
    expect(
      (await repo.authenticatedClient.get<Map<String, dynamic>>('/protected'))
          .data?['ok'],
      isTrue,
    );
  });

  test('native startup restores and rotates the refresh token', () async {
    await store.writeRefreshToken('refresh-old');
    authAdapter.handler = (request) async {
      expect(request.path, '/v1/auth/refresh');
      expect(request.data, {'refreshToken': 'refresh-old'});
      return jsonResponse(200, tokenBody('access-new', 'refresh-new'));
    };
    final repo = repository();

    final session = await repo.restore();

    expect(session?.bookId, 'book-1');
    expect(await store.readRefreshToken(), 'refresh-new');
  });

  test('native startup skips the network without a refresh token', () async {
    final repo = repository();

    expect(await repo.restore(), isNull);
    expect(authAdapter.requests, isEmpty);
  });

  test('web restore relies on cookie mode without reading a token', () async {
    final cookieStore = CookieSessionStore(
      keyValueStore: values,
      idFactory: () => 'web-device',
    );
    authAdapter.handler = (request) async {
      expect(request.data, {'sessionMode': 'cookie'});
      return jsonResponse(200, tokenBody('web-access', null));
    };
    final repo = repository(sessionStore: cookieStore);

    expect((await repo.restore())?.bookId, 'book-1');
    expect(values.values.values, isNot(contains('web-access')));
  });

  test('web rejects a response that exposes a refresh token', () async {
    final cookieStore = CookieSessionStore(
      keyValueStore: values,
      idFactory: () => 'web-device',
    );
    authAdapter.handler = (_) async =>
        jsonResponse(200, tokenBody('web-access', 'exposed-refresh'));
    final repo = repository(sessionStore: cookieStore);

    await expectLater(repo.restore(), throwsFormatException);
    expect(repo.currentSession, isNull);
    expect(values.values.values, isNot(contains('exposed-refresh')));
  });

  test('concurrent 401 responses share one refresh and retry once', () async {
    var refreshCount = 0;
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    authAdapter.handler = (request) async {
      if (request.path.endsWith('/login')) {
        return jsonResponse(200, tokenBody('access-old', 'refresh-old'));
      }
      refreshCount++;
      refreshStarted.complete();
      await releaseRefresh.future;
      return jsonResponse(200, tokenBody('access-new', 'refresh-new'));
    };
    resourceAdapter.handler = (request) async {
      if (request.headers['Authorization'] == 'Bearer access-old') {
        return jsonResponse(401, {'code': 'UNAUTHORIZED'});
      }
      expect(request.headers['Authorization'], 'Bearer access-new');
      return jsonResponse(200, {'ok': true});
    };
    final repo = repository();
    await repo.login(email: 'person@example.com', password: 'password123');

    final first = repo.authenticatedClient.get('/first');
    final second = repo.authenticatedClient.get('/second');
    await refreshStarted.future;
    releaseRefresh.complete();
    final responses = await Future.wait([first, second]);

    expect(responses.map((response) => response.statusCode), everyElement(200));
    expect(refreshCount, 1);
    expect(resourceAdapter.requests, hasLength(4));
  });

  test('a request is not retried again after the refreshed token gets 401',
      () async {
    var refreshCount = 0;
    authAdapter.handler = (request) async {
      if (request.path.endsWith('/login')) {
        return jsonResponse(200, tokenBody('access-old', 'refresh-old'));
      }
      refreshCount++;
      return jsonResponse(200, tokenBody('access-new', 'refresh-new'));
    };
    resourceAdapter.handler =
        (_) async => jsonResponse(401, {'code': 'UNAUTHORIZED'});
    final repo = repository();
    await repo.login(email: 'person@example.com', password: 'password123');

    await expectLater(
      repo.authenticatedClient.get('/still-unauthorized'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCount, 1);
    expect(resourceAdapter.requests, hasLength(2));
  });

  test('refresh failure clears the session and stored refresh token', () async {
    authAdapter.handler = (request) async {
      if (request.path.endsWith('/login')) {
        return jsonResponse(200, tokenBody('access-old', 'refresh-old'));
      }
      return jsonResponse(401, {'code': 'INVALID_REFRESH'});
    };
    resourceAdapter.handler =
        (_) async => jsonResponse(401, {'code': 'UNAUTHORIZED'});
    final repo = repository();
    await repo.login(email: 'person@example.com', password: 'password123');

    await expectLater(
      repo.authenticatedClient.get('/expired'),
      throwsA(isA<DioException>()),
    );

    expect(repo.currentSession, isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('logout revokes remotely and always clears local authentication',
      () async {
    authAdapter.handler =
        (_) async => jsonResponse(200, tokenBody('access-one', 'refresh-one'));
    resourceAdapter.handler = (request) async {
      expect(request.path, '/v1/auth/logout');
      expect(request.headers['Authorization'], 'Bearer access-one');
      return ResponseBody.fromString('', 204);
    };
    final repo = repository();
    await repo.login(email: 'person@example.com', password: 'password123');

    await repo.logout();

    expect(repo.currentSession, isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('logout clears local authentication when revocation is offline',
      () async {
    authAdapter.handler =
        (_) async => jsonResponse(200, tokenBody('access-one', 'refresh-one'));
    resourceAdapter.handler = (request) async {
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    };
    final repo = repository();
    await repo.login(email: 'person@example.com', password: 'password123');

    await expectLater(repo.logout(), throwsA(isA<DioException>()));

    expect(repo.currentSession, isNull);
    expect(await store.readRefreshToken(), isNull);
  });
}

Map<String, dynamic> tokenBody(String access, String? refresh) => {
      'accessToken': access,
      if (refresh != null) 'refreshToken': refresh,
      'tokenType': 'Bearer',
      'expiresIn': 900,
      'bookId': 'book-1',
      'plan': 'free',
    };

ResponseBody jsonResponse(int status, Object body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

typedef AdapterHandler = Future<ResponseBody> Function(RequestOptions request);

class CallbackAdapter implements HttpClientAdapter {
  AdapterHandler? handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final callback = handler;
    if (callback == null) {
      throw StateError('No handler for ${options.method} ${options.path}');
    }
    return callback(options);
  }

  @override
  void close({bool force = false}) {}
}
