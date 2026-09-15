import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/api_endpoint.dart';

class SyncApi {
  SyncApi({
    required Dio dio,
    Dio? uploadDio,
    bool isRelease = kReleaseMode,
    bool isWeb = kIsWeb,
    bool requireHttps = ApiEndpoint.requireHttps,
  })  : _dio = dio,
        _uploadDio = uploadDio ?? Dio(),
        _isRelease = isRelease,
        _isWeb = isWeb,
        _requireHttps = requireHttps;

  final Dio _dio;
  final Dio _uploadDio;
  final bool _isRelease;
  final bool _isWeb;
  final bool _requireHttps;

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
    String? fileName,
    String? mimeType,
    int? size,
  }) async {
    final res = await _dio.post(
      '/v1/books/$bookId/attachments/upload-session',
      data: {
        if (transactionId != null) 'transactionId': transactionId,
        if (fileName != null) 'fileName': fileName,
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

  Future<List<Map<String, dynamic>>> listAttachments({
    required String bookId,
  }) async {
    final res = await _dio.get('/v1/books/$bookId/attachments');
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['attachments'] as List? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<void> deleteAttachment({
    required String bookId,
    required String attachmentId,
  }) async {
    await _dio.delete<void>('/v1/books/$bookId/attachments/$attachmentId');
  }

  Future<Map<String, dynamic>> uploadAttachmentPart({
    required String bookId,
    required String attachmentId,
    required int partNumber,
    required Uint8List bytes,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/v1/books/$bookId/attachments/$attachmentId/parts/$partNumber',
      data: bytes,
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
        headers: {
          Headers.contentTypeHeader: 'application/octet-stream',
        },
      ),
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> multipartPartUploadUrl({
    required String bookId,
    required String attachmentId,
    required int partNumber,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/books/$bookId/attachments/$attachmentId/parts/$partNumber/upload-url',
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> completeMultipartPart({
    required String bookId,
    required String attachmentId,
    required int partNumber,
    required String partId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/books/$bookId/attachments/$attachmentId/parts/$partNumber/complete',
      data: {'partId': partId},
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<void> abortMultipartUpload({
    required String bookId,
    required String attachmentId,
  }) async {
    await _dio.delete<void>(
      '/v1/books/$bookId/attachments/$attachmentId/multipart',
    );
  }

  Future<Map<String, dynamic>> multipartUploadStatus({
    required String bookId,
    required String attachmentId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/books/$bookId/attachments/$attachmentId/multipart',
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<String?> putSignedUrl({
    required String uploadUrl,
    required List<int> bytes,
    Map<String, String> headers = const {},
    String? contentType = 'application/octet-stream',
  }) async {
    final uri = ApiEndpoint.validateResourceUrl(
      uploadUrl,
      isRelease: _isRelease,
      isWeb: _isWeb,
      requireHttps: _requireHttps,
    );
    final response = await _uploadDio.put(
      uri.toString(),
      data: bytes,
      options: Options(
        headers: {
          ...headers,
          if (contentType != null) Headers.contentTypeHeader: contentType,
        },
      ),
    );
    return _responseHeader(response.headers, 'etag');
  }

  Future<Uint8List> downloadSignedUrl({
    required String downloadUrl,
  }) async {
    final uri = ApiEndpoint.validateResourceUrl(
      downloadUrl,
      isRelease: _isRelease,
      isWeb: _isWeb,
      requireHttps: _requireHttps,
    );
    final response = await _uploadDio.get<List<int>>(
      uri.toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
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

  Future<List<Map<String, dynamic>>> reportTrend({
    required String bookId,
    int months = 6,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/reports/trend',
      queryParameters: {'months': months},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['series'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> reportBudget({
    required String bookId,
    String? month,
  }) async {
    final res = await _dio.get(
      '/v1/books/$bookId/reports/budget',
      queryParameters: month != null ? {'month': month} : null,
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

  String? _responseHeader(Headers headers, String name) {
    final value = headers.value(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
