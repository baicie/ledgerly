import 'package:dio/dio.dart';

class SyncApi {
  SyncApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

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
    final res = await _dio.post(
      '/v1/books/$bookId/sync/bootstrap',
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
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listInvites({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/invites',
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
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listBudgets({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/budgets',
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
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> completeAttachment({
    required String bookId,
    required String attachmentId,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/attachments/$attachmentId/complete',
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
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listFxRates({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/fx-rates',
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
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listRevisions({
    required String bookId,
    required String transactionId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/transactions/$transactionId/revisions',
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
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listRecurring({
    required String bookId,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/recurring',
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['rules'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
