import 'package:dio/dio.dart';

class SyncApi {
  SyncApi({
    Dio? dio,
    this.baseUrl = 'http://127.0.0.1:8080',
  }) : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 5)));

  final Dio _dio;
  final String baseUrl;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await _dio.post(
      '/v1/auth/register',
      data: {
        'email': email,
        'password': password,
        'displayName': displayName,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final res = await _dio.post(
      '/v1/auth/login',
      data: {
        'email': email,
        'password': password,
        'deviceId': deviceId,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> push({
    required String bookId,
    required String deviceId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/sync/push',
      data: {
        'deviceId': deviceId,
        'mutations': mutations,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> pull({
    required String bookId,
    required int cursor,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/sync/pull',
      queryParameters: {'cursor': cursor, 'limit': 500},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> bootstrap({required String bookId}) async {
    final res = await _dio.post('/v1/books/$bookId/sync/bootstrap');
    return Map<String, dynamic>.from(res.data as Map);
  }
}
