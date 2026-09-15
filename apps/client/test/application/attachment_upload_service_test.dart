import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/attachment_upload_service.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/sync_api.dart';

void main() {
  late AppDatabase db;
  late LocalAttachmentRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalAttachmentRepository(
      db,
      byteStore: MemoryAttachmentByteStore(),
    );
  });

  tearDown(() => db.close());

  test('uploads local bytes and persists the remote attachment id', () async {
    final bytes = Uint8List.fromList(utf8.encode('receipt bytes'));
    final path = await repository.writeBytes(id: 'local-1', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-1',
      bookId: 'book-local',
      transactionId: 'transaction-1',
      fileName: 'receipt.txt',
      mime: 'text/plain',
      relativePath: path,
    );
    final apiAdapter = _ApiAdapter();
    final uploadAdapter = _UploadAdapter();
    final api = SyncApi(
      dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = apiAdapter,
      uploadDio: Dio()..httpClientAdapter = uploadAdapter,
      isRelease: false,
      isWeb: false,
    );
    final auth = _FakeAuth(
      const AuthSession(bookId: 'remote-book', plan: 'plus'),
    );

    final result = await AttachmentUploadService(
      repository: repository,
      api: api,
      auth: auth,
    ).upload(attachment);

    expect(result.attachmentId, 'remote-1');
    expect(result.objectKey, 'books/remote-book/remote-1');
    expect(result.uploadMode, 'direct');
    expect(uploadAdapter.bytes, bytes);
    expect(uploadAdapter.contentType, 'text/plain');
    expect(uploadAdapter.testHeader, 'signed-value');

    final saved = (await repository.list(bookId: 'book-local')).single;
    expect(saved.cloudUploadStatus, AttachmentCloudStatus.ready);
    expect(saved.remoteAttachmentId, 'remote-1');
    expect(saved.remoteObjectKey, 'books/remote-book/remote-1');
    expect(saved.remoteUploadError, isNull);
  });

  test('persists a failed cloud upload and exposes it for retry', () async {
    final bytes = Uint8List.fromList(const [1, 2, 3]);
    final path = await repository.writeBytes(id: 'local-2', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-2',
      bookId: 'book-local',
      transactionId: 'transaction-2',
      fileName: 'receipt.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    final api = SyncApi(
      dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = _ApiAdapter(completeStatusCode: 422),
      uploadDio: Dio()..httpClientAdapter = _UploadAdapter(),
      isRelease: false,
      isWeb: false,
    );
    final service = AttachmentUploadService(
      repository: repository,
      api: api,
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    await expectLater(service.upload(attachment), throwsA(isA<DioException>()));

    final saved = (await repository.list(bookId: 'book-local')).single;
    expect(saved.cloudUploadStatus, AttachmentCloudStatus.failed);
    expect(saved.remoteUploadError, 'UPLOAD_SIZE_MISMATCH');
    expect(saved.retryAttemptCount, 5);
    expect(saved.nextRetryAt, isNull);
  });

  test('automatically retries a transient cloud upload failure', () async {
    final bytes = Uint8List.fromList(const [4, 5, 6]);
    final path = await repository.writeBytes(id: 'local-retry', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-retry',
      bookId: 'book-local',
      transactionId: 'transaction-retry',
      fileName: 'retry.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    final auth = _FakeAuth(
      const AuthSession(bookId: 'remote-book', plan: 'plus'),
    );
    final failing = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = _ApiAdapter(completeStatusCode: 503),
        uploadDio: Dio()..httpClientAdapter = _UploadAdapter(),
        isRelease: false,
        isWeb: false,
      ),
      auth: auth,
    );

    await expectLater(
      failing.upload(attachment),
      throwsA(isA<DioException>()),
    );
    final failed = (await repository.list(bookId: 'book-local')).single;
    expect(failed.cloudUploadStatus, AttachmentCloudStatus.failed);
    expect(failed.retryAttemptCount, 1);
    expect(failed.nextRetryAt, isNotNull);

    final retrying = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = _ApiAdapter(),
        uploadDio: Dio()..httpClientAdapter = _UploadAdapter(),
        isRelease: false,
        isWeb: false,
      ),
      auth: auth,
    );
    final report = await retrying.retryFailedUploads(
      localBookId: 'book-local',
      now: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    expect(report.attempted, 1);
    expect(report.succeeded, 1);
    expect(report.failed, 0);
    final ready = (await repository.list(bookId: 'book-local')).single;
    expect(ready.cloudUploadStatus, AttachmentCloudStatus.ready);
    expect(ready.retryAttemptCount, 0);
    expect(ready.nextRetryAt, isNull);
  });

  test('downloads remote attachments and removes deleted remote copies',
      () async {
    final stalePath = await repository.writeBytes(
      id: 'stale-local',
      bytes: Uint8List.fromList(utf8.encode('stale')),
    );
    final stale = await repository.insert(
      id: 'stale-local',
      bookId: 'book-local',
      transactionId: 'transaction-old',
      fileName: 'old.txt',
      mime: 'text/plain',
      relativePath: stalePath,
    );
    await repository.markCloudReady(
      id: stale.id,
      remoteAttachmentId: 'remote-old',
      remoteObjectKey: 'books/remote-book/remote-old',
    );
    final remoteBytes = Uint8List.fromList(utf8.encode('remote bytes'));
    final api = SyncApi(
      dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = _ApiAdapter(
          attachments: [
            {
              'id': 'remote-new',
              'transactionId': 'transaction-new',
              'fileName': 'new.txt',
              'objectKey': 'books/remote-book/remote-new',
              'contentHash': null,
              'mimeType': 'text/plain',
              'sizeBytes': remoteBytes.length,
              'uploadStatus': 'ready',
              'createdAt': '2026-09-14T00:00:00Z',
              'downloadUrl': 'https://storage.test/download/remote-new',
              'downloadMode': 'direct',
            },
          ],
        ),
      uploadDio: Dio()
        ..httpClientAdapter = _UploadAdapter(downloadBytes: remoteBytes),
      isRelease: false,
      isWeb: false,
    );
    final service = AttachmentUploadService(
      repository: repository,
      api: api,
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    final result = await service.syncRemote(localBookId: 'book-local');

    expect(result.remoteCount, 1);
    expect(result.downloaded, 1);
    expect(result.refreshed, 1);
    expect(result.deleted, 1);
    final items = await repository.list(bookId: 'book-local');
    expect(items, hasLength(1));
    expect(items.single.id, 'remote-new');
    expect(items.single.fileName, 'new.txt');
    expect(items.single.cloudUploadStatus, AttachmentCloudStatus.ready);
    expect(await repository.readBytes(items.single.relativePath), remoteBytes);
    expect(await repository.readBytes(stale.relativePath), isNull);
  });

  test('deletes the remote object before removing a local attachment',
      () async {
    final path = await repository.writeBytes(
      id: 'local-delete',
      bytes: Uint8List.fromList(const [7, 8, 9]),
    );
    final attachment = await repository.insert(
      id: 'local-delete',
      bookId: 'book-local',
      transactionId: 'transaction-delete',
      fileName: 'delete.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    await repository.markCloudReady(
      id: attachment.id,
      remoteAttachmentId: 'remote-delete',
      remoteObjectKey: 'books/remote-book/remote-delete',
    );
    final apiAdapter = _ApiAdapter();
    final service = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = apiAdapter,
        uploadDio: Dio()..httpClientAdapter = _UploadAdapter(),
        isRelease: false,
        isWeb: false,
      ),
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    await service.deleteAttachment(
      (await repository.list(bookId: 'book-local')).single,
    );

    expect(apiAdapter.deletedIds, ['remote-delete']);
    expect(await repository.list(bookId: 'book-local'), isEmpty);
    expect(await repository.readBytes(path), isNull);
  });

  test('streams a large attachment through multipart parts', () async {
    final bytes = Uint8List.fromList(List.generate(8, (index) => index));
    final path =
        await repository.writeBytes(id: 'local-multipart', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-multipart',
      bookId: 'book-local',
      transactionId: 'transaction-multipart',
      fileName: 'large.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    final adapter = _ApiAdapter(multipart: true, partSizeBytes: 3);
    final service = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = adapter,
        uploadDio: Dio()..httpClientAdapter = _UploadAdapter(),
        isRelease: false,
        isWeb: false,
      ),
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    final result = await service.upload(attachment);

    expect(result.uploadMode, 'multipart');
    expect(adapter.uploadedParts.keys, [1, 2, 3]);
    expect(adapter.uploadedParts[1], bytes.sublist(0, 3));
    expect(adapter.uploadedParts[2], bytes.sublist(3, 6));
    expect(adapter.uploadedParts[3], bytes.sublist(6, 8));
    final saved = (await repository.list(bookId: 'book-local')).single;
    expect(saved.cloudUploadStatus, AttachmentCloudStatus.ready);
  });

  test('resumes multipart upload from server-reported completed parts',
      () async {
    final bytes = Uint8List.fromList(List.generate(8, (index) => index));
    final path = await repository.writeBytes(id: 'local-resume', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-resume',
      bookId: 'book-local',
      transactionId: 'transaction-resume',
      fileName: 'resume.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    await repository.markCloudUploadStarted(
      id: attachment.id,
      remoteAttachmentId: 'remote-existing',
      remoteObjectKey: 'books/remote-book/remote-existing',
      uploadMode: 'multipart',
      partSizeBytes: 3,
    );
    final adapter = _ApiAdapter(
      multipart: true,
      partSizeBytes: 3,
      multipartStatus: 'pending',
      uploadedPartNumbers: const [1],
    );
    final service = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = adapter,
        uploadDio: Dio()..httpClientAdapter = _UploadAdapter(),
        isRelease: false,
        isWeb: false,
      ),
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    final result = await service.upload(
      (await repository.list(bookId: 'book-local')).single,
    );

    expect(result.uploadMode, 'multipart');
    expect(adapter.sessionRequests, 0);
    expect(adapter.uploadedParts.keys.toSet(), {2, 3});
    final saved = (await repository.list(bookId: 'book-local')).single;
    expect(saved.cloudUploadStatus, AttachmentCloudStatus.ready);
  });

  test('uploads multipart parts directly and registers returned etags',
      () async {
    final bytes = Uint8List.fromList(List.generate(8, (index) => index));
    final path =
        await repository.writeBytes(id: 'local-direct-parts', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-direct-parts',
      bookId: 'book-local',
      transactionId: 'transaction-direct-parts',
      fileName: 'direct.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    final adapter = _ApiAdapter(
      multipart: true,
      partSizeBytes: 3,
      directParts: true,
    );
    final uploadAdapter = _UploadAdapter(etag: '"direct-etag"');
    final service = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = adapter,
        uploadDio: Dio()..httpClientAdapter = uploadAdapter,
        isRelease: false,
        isWeb: false,
      ),
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    final result = await service.upload(attachment);

    expect(result.uploadMode, 'multipart');
    expect(uploadAdapter.uploadedPaths, hasLength(3));
    expect(adapter.uploadedParts, isEmpty);
    expect(adapter.registeredParts, {
      1: '"direct-etag"',
      2: '"direct-etag"',
      3: '"direct-etag"',
    });
    final saved = (await repository.list(bookId: 'book-local')).single;
    expect(saved.cloudUploadStatus, AttachmentCloudStatus.ready);
  });

  test('falls back to proxy when a direct multipart PUT fails', () async {
    final bytes = Uint8List.fromList(List.generate(8, (index) => index));
    final path =
        await repository.writeBytes(id: 'local-direct-fallback', bytes: bytes);
    final attachment = await repository.insert(
      id: 'local-direct-fallback',
      bookId: 'book-local',
      transactionId: 'transaction-direct-fallback',
      fileName: 'fallback.bin',
      mime: 'application/octet-stream',
      relativePath: path,
    );
    final adapter = _ApiAdapter(
      multipart: true,
      partSizeBytes: 3,
      directParts: true,
    );
    final service = AttachmentUploadService(
      repository: repository,
      api: SyncApi(
        dio: Dio(BaseOptions(baseUrl: 'http://api.test'))
          ..httpClientAdapter = adapter,
        uploadDio: Dio()..httpClientAdapter = _UploadAdapter(failPut: true),
        isRelease: false,
        isWeb: false,
      ),
      auth: _FakeAuth(
        const AuthSession(bookId: 'remote-book', plan: 'plus'),
      ),
    );

    final result = await service.upload(attachment);

    expect(result.uploadMode, 'multipart');
    expect(adapter.registeredParts, isEmpty);
    expect(adapter.uploadedParts.keys, [1, 2, 3]);
    final saved = (await repository.list(bookId: 'book-local')).single;
    expect(saved.cloudUploadStatus, AttachmentCloudStatus.ready);
  });
}

class _ApiAdapter implements HttpClientAdapter {
  _ApiAdapter({
    this.completeStatusCode = 200,
    this.attachments = const [],
    this.multipart = false,
    this.partSizeBytes = 5 * 1024 * 1024,
    this.multipartStatus = 'pending',
    this.uploadedPartNumbers = const [],
    this.directParts = false,
  });

  final int completeStatusCode;
  final List<Map<String, dynamic>> attachments;
  final bool multipart;
  final int partSizeBytes;
  final String multipartStatus;
  final List<int> uploadedPartNumbers;
  final bool directParts;
  final deletedIds = <String>[];
  final uploadedParts = <int, Uint8List>{};
  final registeredParts = <int, String>{};
  var sessionRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path.endsWith('/attachments')) {
      return ResponseBody.fromString(
        jsonEncode({'attachments': attachments}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'GET' && options.path.endsWith('/multipart')) {
      return ResponseBody.fromString(
        jsonEncode({
          'attachmentId': 'remote-existing',
          'objectKey': 'books/remote-book/remote-existing',
          'uploadStatus': multipartStatus,
          'uploadMode': 'multipart',
          'partSizeBytes': partSizeBytes,
          'totalParts': 3,
          'uploadedPartNumbers': uploadedPartNumbers,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'DELETE' && options.path.contains('/attachments/')) {
      deletedIds.add(options.path.split('/').last);
      return ResponseBody.fromString('', 204);
    }
    if (options.method == 'POST' && options.path.endsWith('/upload-url')) {
      final segments = options.path.split('/');
      final partNumber = int.parse(segments[segments.length - 2]);
      return ResponseBody.fromString(
        jsonEncode({
          'partNumber': partNumber,
          'uploadMode': directParts ? 'direct' : 'proxy',
          'uploadUrl':
              directParts ? 'https://storage.test/parts/$partNumber' : null,
          'uploadHeaders': directParts
              ? const {'x-test-header': 'signed-value'}
              : const <String, String>{},
          'expiresIn': 600,
          'totalParts': 3,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'POST' &&
        options.path.endsWith('/complete') &&
        options.path.contains('/parts/')) {
      final segments = options.path.split('/');
      final partNumber = int.parse(segments[segments.length - 2]);
      final chunks = await requestStream?.toList() ?? const <Uint8List>[];
      final body =
          jsonDecode(utf8.decode(chunks.expand((chunk) => chunk).toList()))
              as Map<String, dynamic>;
      registeredParts[partNumber] = body['partId'] as String;
      return ResponseBody.fromString(
        jsonEncode({
          'partNumber': partNumber,
          'partId': body['partId'],
          'uploadedParts': registeredParts.length,
          'totalParts': 3,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'PUT' && options.path.contains('/parts/')) {
      final partNumber = int.parse(options.path.split('/').last);
      final chunks = await requestStream?.toList() ?? const <Uint8List>[];
      uploadedParts[partNumber] = Uint8List.fromList(
        chunks.expand((chunk) => chunk).toList(growable: false),
      );
      return ResponseBody.fromString(
        jsonEncode({
          'partNumber': partNumber,
          'partId': 'part-$partNumber',
          'uploadedParts': uploadedParts.length,
          'totalParts': 3,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'POST' &&
        options.path.endsWith('/attachments/upload-session')) {
      sessionRequests++;
      return ResponseBody.fromString(
        jsonEncode({
          'attachmentId': 'remote-1',
          'objectKey': 'books/remote-book/remote-1',
          'uploadUrl': multipart
              ? null
              : 'https://storage.test/books/remote-book/remote-1',
          'uploadMode': multipart ? 'multipart' : 'direct',
          'uploadHeaders': const <String, String>{
            'x-test-header': 'signed-value',
          },
          'downloadUrl':
              multipart ? null : 'https://storage.test/download/remote-1',
          'downloadMode': multipart ? null : 'direct',
          if (multipart) 'partSizeBytes': partSizeBytes,
          'expiresIn': 600,
          'maxSizeBytes': 100 * 1024 * 1024,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'POST' && options.path.endsWith('/complete')) {
      return ResponseBody.fromString(
        jsonEncode({
          if (completeStatusCode == 200) ...{
            'attachmentId': 'remote-1',
            'uploadStatus': 'ready',
            'downloadUrl': 'https://storage.test/download/remote-1',
          } else ...{
            'code': 'UPLOAD_SIZE_MISMATCH',
            'message': 'uploaded attachment size mismatch',
          },
        }),
        completeStatusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    throw StateError(
        'unexpected API request: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

class _UploadAdapter implements HttpClientAdapter {
  _UploadAdapter({
    this.downloadBytes = const [],
    this.etag,
    this.failPut = false,
  });

  final List<int> downloadBytes;
  final String? etag;
  final bool failPut;
  Uint8List? bytes;
  String? contentType;
  String? testHeader;
  final uploadedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET') {
      return ResponseBody.fromBytes(downloadBytes, 200);
    }
    if (failPut) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    bytes = Uint8List.fromList(
      chunks.expand((chunk) => chunk).toList(growable: false),
    );
    contentType = options.headers[Headers.contentTypeHeader] as String?;
    testHeader = options.headers['x-test-header'] as String?;
    uploadedPaths.add(options.path);
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        if (etag != null) 'etag': [etag!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends ChangeNotifier implements AuthGateway {
  _FakeAuth(this._session);

  final AuthSession? _session;

  @override
  AuthSession? get currentSession => _session;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async =>
      _session!;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession> registerAndLogin({
    required String email,
    required String password,
    required String displayName,
  }) async =>
      _session!;

  @override
  Future<AuthSession?> restore() async => _session;
}
