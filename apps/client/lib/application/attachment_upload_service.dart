import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_repository.dart';
import '../data/ledger_repository.dart';
import '../data/local_attachment_repository.dart';
import '../data/sync_api.dart';

class AttachmentUploadException implements Exception {
  const AttachmentUploadException(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'AttachmentUploadException($code)';
}

class AttachmentUploadResult {
  const AttachmentUploadResult({
    required this.attachmentId,
    required this.objectKey,
    required this.uploadMode,
    this.downloadUrl,
  });

  final String attachmentId;
  final String objectKey;
  final String uploadMode;
  final String? downloadUrl;
}

class AttachmentCloudSyncResult {
  const AttachmentCloudSyncResult({
    required this.remoteCount,
    required this.downloaded,
    required this.refreshed,
    required this.deleted,
  });

  final int remoteCount;
  final int downloaded;
  final int refreshed;
  final int deleted;
}

class AttachmentRetryReport {
  const AttachmentRetryReport({
    required this.attempted,
    required this.succeeded,
    required this.failed,
  });

  final int attempted;
  final int succeeded;
  final int failed;
}

class AttachmentUploadService {
  AttachmentUploadService({
    required LocalAttachmentRepository repository,
    required SyncApi api,
    required AuthGateway auth,
    LedgerRepository? ledger,
  })  : _repository = repository,
        _api = api,
        _auth = auth,
        _ledger = ledger;

  final LocalAttachmentRepository _repository;
  final SyncApi _api;
  final AuthGateway _auth;
  final LedgerRepository? _ledger;

  static const maxAutomaticRetryAttempts = 5;

  Future<AttachmentUploadResult> upload(
    LocalAttachmentRecord attachment,
  ) async {
    final session = _auth.currentSession;
    if (session == null) {
      throw const AttachmentUploadException('not_signed_in');
    }
    await _ensureAccountBinding(attachment.bookId, session);

    await _repository.markCloudUploading(attachment.id);
    String? multipartAttachmentId;
    String? currentRemoteAttachmentId;
    String? currentObjectKey;
    String? currentUploadMode;
    _MultipartSession? multipartSession;
    try {
      final totalBytes = await _repository.byteLength(attachment.relativePath);
      if (totalBytes == null) {
        throw const AttachmentUploadException('attachment_bytes_missing');
      }

      if (attachment.remoteUploadMode == 'multipart' &&
          attachment.remoteAttachmentId != null) {
        try {
          final resumed = await _resumeMultipart(
            bookId: session.bookId,
            attachment: attachment,
            totalBytes: totalBytes,
          );
          if (resumed.uploadStatus == 'ready') {
            await _repository.markCloudReady(
              id: attachment.id,
              remoteAttachmentId: resumed.attachmentId,
              remoteObjectKey: resumed.objectKey,
            );
            return AttachmentUploadResult(
              attachmentId: resumed.attachmentId,
              objectKey: resumed.objectKey,
              uploadMode: 'multipart',
            );
          }
          if (resumed.uploadStatus == 'pending') {
            multipartSession = resumed;
            multipartAttachmentId = resumed.attachmentId;
            currentRemoteAttachmentId = resumed.attachmentId;
            currentObjectKey = resumed.objectKey;
            currentUploadMode = 'multipart';
          } else {
            await _repository.clearRemoteUploadState(attachment.id);
          }
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if (status != 404 && status != 409) rethrow;
          await _repository.clearRemoteUploadState(attachment.id);
        }
      }

      Map<String, dynamic>? completed;
      if (multipartSession == null) {
        final sessionJson = await _api.createUploadSession(
          bookId: session.bookId,
          transactionId: attachment.transactionId,
          fileName: attachment.fileName,
          mimeType: attachment.mime,
          size: totalBytes,
        );
        final remoteAttachmentId = _requiredString(
          sessionJson,
          'attachmentId',
        );
        final objectKey = _requiredString(sessionJson, 'objectKey');
        final uploadModeValue = sessionJson['uploadMode'];
        final uploadMode =
            uploadModeValue is String && uploadModeValue.isNotEmpty
                ? uploadModeValue
                : 'proxy';
        final maxSizeBytes = _optionalInt(sessionJson['maxSizeBytes']);
        if (maxSizeBytes != null && totalBytes > maxSizeBytes) {
          throw const AttachmentUploadException('attachment_too_large');
        }
        await _repository.markCloudUploadStarted(
          id: attachment.id,
          remoteAttachmentId: remoteAttachmentId,
          remoteObjectKey: objectKey,
          uploadMode: uploadMode,
          partSizeBytes: _optionalInt(sessionJson['partSizeBytes']),
        );
        currentRemoteAttachmentId = remoteAttachmentId;
        currentObjectKey = objectKey;
        currentUploadMode = uploadMode;
        if (uploadMode == 'multipart') {
          multipartAttachmentId = remoteAttachmentId;
          multipartSession = _multipartSessionFromResponse(
            sessionJson: sessionJson,
            totalBytes: totalBytes,
          );
        } else {
          final bytes = await _repository.readBytes(attachment.relativePath);
          if (bytes == null || bytes.length != totalBytes) {
            throw const AttachmentUploadException('attachment_bytes_missing');
          }
          await _api.putSignedUrl(
            uploadUrl: _requiredString(sessionJson, 'uploadUrl'),
            bytes: bytes,
            headers: _stringMap(sessionJson['uploadHeaders']),
            contentType: attachment.mime,
          );
          completed = await _api.completeAttachment(
            bookId: session.bookId,
            attachmentId: remoteAttachmentId,
          );
        }
      }

      if (multipartSession != null) {
        completed = await _uploadMultipart(
          bookId: session.bookId,
          relativePath: attachment.relativePath,
          totalBytes: totalBytes,
          session: multipartSession,
        );
      }
      if (completed == null) {
        throw const AttachmentUploadException('invalid_session_response');
      }
      if (completed['uploadStatus'] != 'ready') {
        throw const AttachmentUploadException('invalid_complete_response');
      }
      final remoteAttachmentId = multipartSession?.attachmentId ??
          currentRemoteAttachmentId ??
          _requiredString(completed, 'attachmentId');
      final objectKey = multipartSession?.objectKey ??
          currentObjectKey ??
          attachment.remoteObjectKey ??
          _requiredString(completed, 'objectKey');
      await _repository.markCloudReady(
        id: attachment.id,
        remoteAttachmentId: remoteAttachmentId,
        remoteObjectKey: objectKey,
      );
      final downloadUrl = completed['downloadUrl'];
      return AttachmentUploadResult(
        attachmentId: remoteAttachmentId,
        objectKey: objectKey,
        uploadMode: multipartSession == null
            ? (currentUploadMode ?? 'single')
            : 'multipart',
        downloadUrl: downloadUrl is String ? downloadUrl : null,
      );
    } catch (error) {
      final retryable = _isRetryable(error);
      final retryAttemptCount = retryable
          ? (attachment.retryAttemptCount + 1)
              .clamp(0, maxAutomaticRetryAttempts)
          : maxAutomaticRetryAttempts;
      if (multipartAttachmentId != null &&
          (!retryable || retryAttemptCount >= maxAutomaticRetryAttempts)) {
        try {
          await _api.abortMultipartUpload(
            bookId: session.bookId,
            attachmentId: multipartAttachmentId,
          );
        } catch (_) {
          // Server-side TTL cleanup remains the fallback for aborted chunks.
        }
        await _repository.clearRemoteUploadState(attachment.id);
      }
      await _repository.markCloudFailed(
        attachment.id,
        _errorCode(error),
        retryAttemptCount: retryAttemptCount,
        nextRetryAt: retryable && retryAttemptCount < maxAutomaticRetryAttempts
            ? _nextRetryAt(retryAttemptCount)
            : null,
      );
      rethrow;
    }
  }

  Future<_MultipartSession> _resumeMultipart({
    required String bookId,
    required LocalAttachmentRecord attachment,
    required int totalBytes,
  }) async {
    final status = await _api.multipartUploadStatus(
      bookId: bookId,
      attachmentId: attachment.remoteAttachmentId!,
    );
    final objectKey = _requiredString(status, 'objectKey');
    final uploadStatus = _requiredString(status, 'uploadStatus');
    final partSize =
        _optionalInt(status['partSizeBytes']) ?? attachment.remotePartSizeBytes;
    if (partSize == null || partSize <= 0) {
      throw const AttachmentUploadException('invalid_session_response');
    }
    final totalParts = _optionalInt(status['totalParts']) ??
        (totalBytes + partSize - 1) ~/ partSize;
    final uploaded = <int>{};
    final rawUploaded = status['uploadedPartNumbers'];
    if (rawUploaded is List) {
      for (final value in rawUploaded) {
        if (value is num) uploaded.add(value.toInt());
      }
    }
    return _MultipartSession(
      attachmentId: attachment.remoteAttachmentId!,
      objectKey: objectKey,
      uploadStatus: uploadStatus,
      partSizeBytes: partSize,
      totalParts: totalParts,
      uploadedParts: uploaded,
    );
  }

  _MultipartSession _multipartSessionFromResponse({
    required Map<String, dynamic> sessionJson,
    required int totalBytes,
  }) {
    final attachmentId = _requiredString(sessionJson, 'attachmentId');
    final objectKey = _requiredString(sessionJson, 'objectKey');
    final partSize = _optionalInt(sessionJson['partSizeBytes']);
    if (partSize == null || partSize <= 0) {
      throw const AttachmentUploadException('invalid_session_response');
    }
    final totalParts = (totalBytes + partSize - 1) ~/ partSize;
    if (totalParts <= 0 || totalParts > 10000) {
      throw const AttachmentUploadException('attachment_too_large');
    }
    return _MultipartSession(
      attachmentId: attachmentId,
      objectKey: objectKey,
      uploadStatus: 'pending',
      partSizeBytes: partSize,
      totalParts: totalParts,
      uploadedParts: <int>{},
    );
  }

  Future<Map<String, dynamic>> _uploadMultipart({
    required String bookId,
    required String relativePath,
    required int totalBytes,
    required _MultipartSession session,
  }) async {
    final missingParts = [
      for (var partNumber = 1; partNumber <= session.totalParts; partNumber++)
        if (!session.uploadedParts.contains(partNumber)) partNumber,
    ];
    const concurrency = 3;
    for (var offset = 0; offset < missingParts.length; offset += concurrency) {
      final end = (offset + concurrency < missingParts.length)
          ? offset + concurrency
          : missingParts.length;
      await Future.wait([
        for (final partNumber in missingParts.sublist(offset, end))
          _uploadMultipartPart(
            bookId: bookId,
            relativePath: relativePath,
            totalBytes: totalBytes,
            session: session,
            partNumber: partNumber,
          ),
      ]);
    }
    return _api.completeAttachment(
      bookId: bookId,
      attachmentId: session.attachmentId,
    );
  }

  Future<void> _uploadMultipartPart({
    required String bookId,
    required String relativePath,
    required int totalBytes,
    required _MultipartSession session,
    required int partNumber,
  }) async {
    final start = (partNumber - 1) * session.partSizeBytes;
    final nextPartEnd = start + session.partSizeBytes;
    final end = nextPartEnd < totalBytes ? nextPartEnd : totalBytes;
    final bytes = await _repository.readRange(
      relativePath,
      start: start,
      end: end,
    );
    if (bytes == null || bytes.length != end - start) {
      throw const AttachmentUploadException('attachment_bytes_missing');
    }

    final upload = await _api.multipartPartUploadUrl(
      bookId: bookId,
      attachmentId: session.attachmentId,
      partNumber: partNumber,
    );
    final uploadMode = upload['uploadMode'];
    if (uploadMode == 'direct') {
      try {
        final etag = await _api.putSignedUrl(
          uploadUrl: _requiredString(upload, 'uploadUrl'),
          bytes: bytes,
          headers: _stringMap(upload['uploadHeaders']),
          contentType: 'application/octet-stream',
        );
        if (etag != null) {
          await _api.completeMultipartPart(
            bookId: bookId,
            attachmentId: session.attachmentId,
            partNumber: partNumber,
            partId: etag,
          );
          session.uploadedParts.add(partNumber);
          return;
        }
      } on DioException {
        // Re-uploading the same part through the proxy is safe.
      }
    } else if (uploadMode != 'proxy') {
      throw const AttachmentUploadException('invalid_session_response');
    }

    final uploaded = await _api.uploadAttachmentPart(
      bookId: bookId,
      attachmentId: session.attachmentId,
      partNumber: partNumber,
      bytes: bytes,
    );
    _requiredString(uploaded, 'partId');
    session.uploadedParts.add(partNumber);
  }

  Future<AttachmentRetryReport> retryFailedUploads({
    required String localBookId,
    DateTime? now,
    int limit = 10,
  }) async {
    final session = _auth.currentSession;
    if (session == null) {
      throw const AttachmentUploadException('not_signed_in');
    }
    await _ensureAccountBinding(localBookId, session);
    final candidates = await _repository.listCloudRetryCandidates(
      bookId: localBookId,
      maxAttempts: maxAutomaticRetryAttempts,
      now: now ?? DateTime.now().toUtc(),
      limit: limit,
    );
    var succeeded = 0;
    var failed = 0;
    for (final attachment in candidates) {
      try {
        await upload(attachment);
        succeeded++;
      } catch (_) {
        failed++;
      }
    }
    return AttachmentRetryReport(
      attempted: candidates.length,
      succeeded: succeeded,
      failed: failed,
    );
  }

  Future<AttachmentCloudSyncResult> syncRemote({
    required String localBookId,
  }) async {
    final session = _auth.currentSession;
    if (session == null) {
      throw const AttachmentUploadException('not_signed_in');
    }
    await _ensureAccountBinding(localBookId, session);
    final rows = await _api.listAttachments(bookId: session.bookId);
    final remoteReady = <String, _RemoteAttachment>{};
    for (final row in rows) {
      final remote = _parseRemoteAttachment(row);
      if (remote.status == 'ready') {
        remoteReady[remote.id] = remote;
      }
    }

    final local = await _repository.list(bookId: localBookId);
    final localByIdentity = <String, LocalAttachmentRecord>{};
    for (final attachment in local) {
      final remoteId = attachment.remoteAttachmentId;
      if (remoteId != null) localByIdentity[remoteId] = attachment;
      localByIdentity[attachment.id] = attachment;
    }

    var downloaded = 0;
    var refreshed = 0;
    for (final remote in remoteReady.values) {
      final existing = localByIdentity[remote.id];
      Uint8List bytes;
      String relativePath;
      final existingBytes = existing == null
          ? null
          : await _repository.readBytes(existing.relativePath);
      if (existingBytes == null ||
          (remote.sizeBytes != null &&
              existingBytes.length != remote.sizeBytes)) {
        bytes = await _downloadRemote(remote);
        relativePath = await _repository.writeBytes(
          id: existing?.id ?? remote.id,
          bytes: bytes,
        );
        downloaded++;
      } else {
        bytes = existingBytes;
        relativePath = existing!.relativePath;
      }
      if (remote.sizeBytes != null && bytes.length != remote.sizeBytes) {
        throw const AttachmentUploadException(
            'remote_attachment_size_mismatch');
      }
      await _repository.upsertRemote(
        remoteAttachmentId: remote.id,
        bookId: localBookId,
        transactionId: remote.transactionId,
        fileName: remote.fileName,
        mime: remote.mime,
        relativePath: relativePath,
        createdAt: remote.createdAt,
        remoteObjectKey: remote.objectKey,
      );
      refreshed++;
    }

    var deleted = 0;
    for (final attachment in local) {
      final remoteId = attachment.remoteAttachmentId;
      if (attachment.cloudUploadStatus != AttachmentCloudStatus.ready ||
          remoteId == null ||
          remoteReady.containsKey(remoteId)) {
        continue;
      }
      await _repository.deleteBytes(attachment.relativePath);
      await _repository.delete(attachment.id);
      deleted++;
    }

    return AttachmentCloudSyncResult(
      remoteCount: remoteReady.length,
      downloaded: downloaded,
      refreshed: refreshed,
      deleted: deleted,
    );
  }

  Future<void> deleteAttachment(LocalAttachmentRecord attachment) async {
    final remoteId = attachment.remoteAttachmentId;
    if (attachment.cloudUploadStatus == AttachmentCloudStatus.ready &&
        remoteId != null) {
      final session = _auth.currentSession;
      if (session == null) {
        throw const AttachmentUploadException('not_signed_in');
      }
      await _ensureAccountBinding(attachment.bookId, session);
      try {
        await _api.deleteAttachment(
          bookId: session.bookId,
          attachmentId: remoteId,
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
    }
    await _repository.deleteBytes(attachment.relativePath);
    await _repository.delete(attachment.id);
  }

  Future<void> _ensureAccountBinding(
    String localBookId,
    AuthSession session,
  ) async {
    final syncState = await _ledger?.syncState(localBookId);
    if (_ledger != null && syncState?.remoteBookId == null) {
      throw const AttachmentUploadException('book_not_bound');
    }
    if (syncState?.remoteBookId != null &&
        syncState!.remoteBookId != session.bookId) {
      throw const AttachmentUploadException('book_bound_to_other_account');
    }
  }

  DateTime _nextRetryAt(int attemptCount) {
    final exponent = (attemptCount - 1).clamp(0, 8);
    final minutes = (1 << exponent).clamp(1, 360);
    return DateTime.now().toUtc().add(Duration(minutes: minutes));
  }

  bool _isRetryable(Object error) {
    if (error is AttachmentUploadException) {
      return !const {
        'attachment_too_large',
        'attachment_bytes_missing',
        'invalid_session_response',
        'invalid_complete_response',
        'book_not_bound',
        'book_bound_to_other_account',
      }.contains(error.code);
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      return status == null || status == 429 || status >= 500;
    }
    return true;
  }

  Future<Uint8List> _downloadRemote(_RemoteAttachment remote) async {
    final downloadUrl = remote.downloadUrl;
    if (downloadUrl == null) {
      throw const AttachmentUploadException('remote_download_url_missing');
    }
    return _api.downloadSignedUrl(downloadUrl: downloadUrl);
  }

  _RemoteAttachment _parseRemoteAttachment(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final objectKey = _requiredString(json, 'objectKey');
    final status = _requiredString(json, 'uploadStatus');
    final transactionId = json['transactionId'];
    final fileName = json['fileName'];
    final mimeType = json['mimeType'];
    final sizeBytes = _optionalInt(json['sizeBytes']);
    final downloadUrl = json['downloadUrl'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    return _RemoteAttachment(
      id: id,
      objectKey: objectKey,
      status: status,
      transactionId: transactionId is String ? transactionId : '',
      fileName:
          fileName is String && fileName.isNotEmpty ? fileName : 'attachment',
      mime: mimeType is String && mimeType.isNotEmpty
          ? mimeType
          : 'application/octet-stream',
      sizeBytes: sizeBytes,
      downloadUrl: downloadUrl is String ? downloadUrl : null,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw const AttachmentUploadException('invalid_session_response');
    }
    return value;
  }

  int? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    throw const AttachmentUploadException('invalid_session_response');
  }

  Map<String, String> _stringMap(Object? value) {
    if (value == null) return const {};
    if (value is! Map) {
      throw const AttachmentUploadException('invalid_session_response');
    }
    final headers = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const AttachmentUploadException('invalid_session_response');
      }
      headers[entry.key as String] = entry.value as String;
    }
    return headers;
  }

  String _errorCode(Object error) {
    if (error is AttachmentUploadException) return error.code;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final code = data['code'];
        if (code is String && code.isNotEmpty) return code;
        final message = data['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      return error.type.name;
    }
    return error.runtimeType.toString();
  }
}

class _RemoteAttachment {
  const _RemoteAttachment({
    required this.id,
    required this.objectKey,
    required this.status,
    required this.transactionId,
    required this.fileName,
    required this.mime,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.createdAt,
  });

  final String id;
  final String objectKey;
  final String status;
  final String transactionId;
  final String fileName;
  final String mime;
  final int? sizeBytes;
  final String? downloadUrl;
  final DateTime createdAt;
}

class _MultipartSession {
  _MultipartSession({
    required this.attachmentId,
    required this.objectKey,
    required this.uploadStatus,
    required this.partSizeBytes,
    required this.totalParts,
    required this.uploadedParts,
  });

  final String attachmentId;
  final String objectKey;
  final String uploadStatus;
  final int partSizeBytes;
  final int totalParts;
  final Set<int> uploadedParts;
}
