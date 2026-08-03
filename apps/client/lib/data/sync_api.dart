import 'package:dio/dio.dart';

class SyncApi {
  SyncApi({
    Dio? dio,
    this.baseUrl = 'http://127.0.0.1:8080',
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 5),
            ));

  final Dio _dio;
  final String baseUrl;
  String? _accessToken;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  Options _authOptions() {
    final headers = <String, dynamic>{};
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return Options(headers: headers);
  }

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
    final data = Map<String, dynamic>.from(res.data as Map);
    setAccessToken(data['accessToken'] as String?);
    return data;
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
      options: _authOptions(),
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
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> bootstrap({required String bookId}) async {
    final res = await _dio.post(
      '/v1/books/$bookId/sync/bootstrap',
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createInvite({
    required String bookId,
    required String email,
    String role = 'editor',
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/invites',
      data: {'email': email, 'role': role},
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listInvites({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/invites',
      options: _authOptions(),
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['invites'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createBudget({
    required String bookId,
    required String name,
    required String amountMinor,
    String currency = 'CNY',
    String? categoryAccountId,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/budgets',
      data: {
        'name': name,
        'amountMinor': amountMinor,
        'currency': currency,
        if (categoryAccountId != null) 'categoryAccountId': categoryAccountId,
      },
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listBudgets({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/budgets',
      options: _authOptions(),
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['budgets'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createUploadSession({
    required String bookId,
    String? transactionId,
    String? mimeType,
    int? size,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/attachments/upload-session',
      data: {
        if (transactionId != null) 'transactionId': transactionId,
        if (mimeType != null) 'mimeType': mimeType,
        if (size != null) 'size': size,
      },
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> completeAttachment({
    required String bookId,
    required String attachmentId,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/attachments/$attachmentId/complete',
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> putSignedUrl({
    required String uploadUrl,
    required List<int> bytes,
  }) async {
    await Dio().put(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: {
          Headers.contentTypeHeader: 'application/octet-stream',
        },
      ),
    );
  }

  Future<Map<String, dynamic>> reportSummary({
    required String bookId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/reports/summary',
      queryParameters: {'from': from, 'to': to},
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listFxRates({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/fx-rates',
      options: _authOptions(),
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['rates'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> upsertFxRate({
    required String bookId,
    required String baseCurrency,
    required String quoteCurrency,
    required double rate,
  }) async {
    final res = await _dio.put(
      '/v1/books/$bookId/fx-rates',
      data: {
        'baseCurrency': baseCurrency,
        'quoteCurrency': quoteCurrency,
        'rate': rate,
      },
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listRevisions({
    required String bookId,
    required String transactionId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/transactions/$transactionId/revisions',
      options: _authOptions(),
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['revisions'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> devUpgrade({required String plan}) async {
    final res = await _dio.post(
      '/v1/billing/dev-upgrade',
      data: {'plan': plan},
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createRecurring({
    required String bookId,
    required String name,
    required Map<String, dynamic> payload,
    bool runNow = false,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/recurring',
      data: {'name': name, 'payload': payload, 'runNow': runNow},
      options: _authOptions(),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listRecurring({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/recurring',
      options: _authOptions(),
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['rules'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
