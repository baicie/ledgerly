import 'dart:io' as dart_io;

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

enum AttachmentCloudStatus {
  local,
  uploading,
  ready,
  failed;

  static AttachmentCloudStatus parse(String? value) {
    return AttachmentCloudStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => AttachmentCloudStatus.local,
    );
  }
}

class LocalAttachmentRecord {
  const LocalAttachmentRecord({
    required this.id,
    required this.bookId,
    required this.transactionId,
    required this.fileName,
    required this.mime,
    required this.relativePath,
    required this.createdAt,
    this.cloudUploadStatus = AttachmentCloudStatus.local,
    this.remoteAttachmentId,
    this.remoteObjectKey,
    this.remoteUploadError,
    this.retryAttemptCount = 0,
    this.nextRetryAt,
    this.remoteUploadMode,
    this.remotePartSizeBytes,
  });

  final String id;
  final String bookId;
  final String transactionId;
  final String fileName;
  final String mime;
  final String relativePath;
  final DateTime createdAt;
  final AttachmentCloudStatus cloudUploadStatus;
  final String? remoteAttachmentId;
  final String? remoteObjectKey;
  final String? remoteUploadError;
  final int retryAttemptCount;
  final DateTime? nextRetryAt;
  final String? remoteUploadMode;
  final int? remotePartSizeBytes;
}

class LocalAttachmentRepository {
  LocalAttachmentRepository(this._db, {AttachmentByteStore? byteStore})
      : _byteStore = byteStore ?? FileAttachmentByteStore();

  final AppDatabase _db;
  final AttachmentByteStore _byteStore;

  /// Read raw bytes for an attachment path. Returns `null` when the
  /// binary has been wiped (orphan metadata) so callers can decide
  /// whether to skip the record or surface a warning.
  Future<Uint8List?> readBytes(String relativePath) =>
      _byteStore.read(relativePath);

  Future<int?> byteLength(String relativePath) =>
      _byteStore.length(relativePath);

  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int end,
  }) =>
      _byteStore.readRange(relativePath, start: start, end: end);

  /// Persist raw bytes for an attachment and return the path it was
  /// written to. Used by the backup restore flow to rehydrate the
  /// binary side of an attachment after a cross-device restore.
  Future<String> writeBytes({
    required String id,
    required Uint8List bytes,
  }) =>
      _byteStore.write(id: id, bytes: bytes);

  /// Drop the binary behind an attachment. Metadata stays so the
  /// caller can still see "附件被清空" in the UI.
  Future<void> deleteBytes(String relativePath) =>
      _byteStore.delete(relativePath);

  Future<List<LocalAttachmentRecord>> list({
    required String bookId,
    String? transactionId,
  }) async {
    final rows = transactionId == null
        ? await _db.customSelect(
            'SELECT * FROM local_attachments WHERE book_id = ? ORDER BY created_at DESC',
            variables: [Variable<String>(bookId)],
            readsFrom: {},
          ).get()
        : await _db.customSelect(
            '''
SELECT * FROM local_attachments
WHERE book_id = ? AND transaction_id = ?
ORDER BY created_at DESC
''',
            variables: [
              Variable<String>(bookId),
              Variable<String>(transactionId),
            ],
            readsFrom: {},
          ).get();
    return [for (final row in rows) _map(row)];
  }

  Future<LocalAttachmentRecord> insert({
    String? id,
    required String bookId,
    required String transactionId,
    required String fileName,
    required String mime,
    required String relativePath,
  }) async {
    final record = LocalAttachmentRecord(
      id: id ?? const Uuid().v4(),
      bookId: bookId,
      transactionId: transactionId,
      fileName: fileName,
      mime: mime,
      relativePath: relativePath,
      createdAt: DateTime.now().toUtc(),
    );
    await _db.customStatement(
      '''
INSERT INTO local_attachments
  (id, book_id, transaction_id, file_name, mime, relative_path, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
      [
        record.id,
        record.bookId,
        record.transactionId,
        record.fileName,
        record.mime,
        record.relativePath,
        record.createdAt.millisecondsSinceEpoch,
      ],
    );
    return record;
  }

  Future<void> delete(String id) {
    return _db.customStatement(
      'DELETE FROM local_attachments WHERE id = ?',
      [id],
    );
  }

  Future<void> markCloudUploading(String id) {
    return _db.customStatement(
      '''
UPDATE local_attachments
SET cloud_upload_status = ?, remote_upload_error = NULL
WHERE id = ?
''',
      [AttachmentCloudStatus.uploading.name, id],
    );
  }

  Future<void> markCloudUploadStarted({
    required String id,
    required String remoteAttachmentId,
    required String remoteObjectKey,
    required String uploadMode,
    int? partSizeBytes,
  }) {
    return _db.customStatement(
      '''
UPDATE local_attachments
SET cloud_upload_status = ?,
    remote_attachment_id = ?,
    remote_object_key = ?,
    remote_upload_mode = ?,
    remote_part_size_bytes = ?,
    remote_upload_error = NULL
WHERE id = ?
''',
      [
        AttachmentCloudStatus.uploading.name,
        remoteAttachmentId,
        remoteObjectKey,
        uploadMode,
        partSizeBytes,
        id,
      ],
    );
  }

  Future<void> markCloudReady({
    required String id,
    required String remoteAttachmentId,
    required String remoteObjectKey,
  }) {
    return _db.customStatement(
      '''
UPDATE local_attachments
SET cloud_upload_status = ?,
    remote_attachment_id = ?,
    remote_object_key = ?,
    remote_upload_error = NULL,
    retry_attempt_count = 0,
    next_retry_at = NULL
WHERE id = ?
''',
      [
        AttachmentCloudStatus.ready.name,
        remoteAttachmentId,
        remoteObjectKey,
        id,
      ],
    );
  }

  Future<void> markCloudFailed(
    String id,
    String error, {
    required int retryAttemptCount,
    required DateTime? nextRetryAt,
  }) {
    return _db.customStatement(
      '''
UPDATE local_attachments
SET cloud_upload_status = ?,
    remote_upload_error = ?,
    retry_attempt_count = ?,
    next_retry_at = ?
WHERE id = ?
''',
      [
        AttachmentCloudStatus.failed.name,
        error,
        retryAttemptCount,
        nextRetryAt?.millisecondsSinceEpoch,
        id,
      ],
    );
  }

  Future<List<LocalAttachmentRecord>> listCloudRetryCandidates({
    required String bookId,
    required int maxAttempts,
    required DateTime now,
    int limit = 10,
  }) async {
    final rows = await _db.customSelect(
      '''
SELECT * FROM local_attachments
WHERE book_id = ?
  AND cloud_upload_status = ?
  AND retry_attempt_count < ?
  AND (next_retry_at IS NULL OR next_retry_at <= ?)
ORDER BY next_retry_at, created_at
LIMIT ?
''',
      variables: [
        Variable<String>(bookId),
        Variable<String>(AttachmentCloudStatus.failed.name),
        Variable<int>(maxAttempts),
        Variable<int>(now.millisecondsSinceEpoch),
        Variable<int>(limit),
      ],
      readsFrom: {},
    ).get();
    return [for (final row in rows) _map(row)];
  }

  Future<LocalAttachmentRecord> upsertRemote({
    required String remoteAttachmentId,
    required String bookId,
    required String transactionId,
    required String fileName,
    required String mime,
    required String relativePath,
    required DateTime createdAt,
    required String remoteObjectKey,
  }) async {
    final rows = await _db.customSelect(
      '''
SELECT * FROM local_attachments
WHERE book_id = ? AND (id = ? OR remote_attachment_id = ?)
LIMIT 1
''',
      variables: [
        Variable<String>(bookId),
        Variable<String>(remoteAttachmentId),
        Variable<String>(remoteAttachmentId),
      ],
      readsFrom: {},
    ).get();
    final existing = rows.isEmpty ? null : _map(rows.single);
    if (existing == null) {
      final record = LocalAttachmentRecord(
        id: remoteAttachmentId,
        bookId: bookId,
        transactionId: transactionId,
        fileName: fileName,
        mime: mime,
        relativePath: relativePath,
        createdAt: createdAt,
        cloudUploadStatus: AttachmentCloudStatus.ready,
        remoteAttachmentId: remoteAttachmentId,
        remoteObjectKey: remoteObjectKey,
      );
      await _db.customStatement(
        '''
INSERT INTO local_attachments
  (id, book_id, transaction_id, file_name, mime, relative_path,
   cloud_upload_status, remote_attachment_id, remote_object_key, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          record.id,
          record.bookId,
          record.transactionId,
          record.fileName,
          record.mime,
          record.relativePath,
          record.cloudUploadStatus.name,
          record.remoteAttachmentId,
          record.remoteObjectKey,
          record.createdAt.millisecondsSinceEpoch,
        ],
      );
      return record;
    }

    await _db.customStatement(
      '''
UPDATE local_attachments
SET transaction_id = ?,
    file_name = ?,
    mime = ?,
    relative_path = ?,
    cloud_upload_status = ?,
    remote_attachment_id = ?,
    remote_object_key = ?,
    remote_upload_error = NULL,
    retry_attempt_count = 0,
    next_retry_at = NULL,
    remote_upload_mode = NULL,
    remote_part_size_bytes = NULL,
    created_at = ?
WHERE id = ?
''',
      [
        transactionId,
        fileName,
        mime,
        relativePath,
        AttachmentCloudStatus.ready.name,
        remoteAttachmentId,
        remoteObjectKey,
        createdAt.millisecondsSinceEpoch,
        existing.id,
      ],
    );
    return LocalAttachmentRecord(
      id: existing.id,
      bookId: bookId,
      transactionId: transactionId,
      fileName: fileName,
      mime: mime,
      relativePath: relativePath,
      createdAt: createdAt,
      cloudUploadStatus: AttachmentCloudStatus.ready,
      remoteAttachmentId: remoteAttachmentId,
      remoteObjectKey: remoteObjectKey,
    );
  }

  /// Bulk-read every attachment across all books. Used by
  /// backup/restore so a single call covers every book.
  Future<List<LocalAttachmentRecord>> listAll() async {
    final rows = await _db.customSelect(
      'SELECT * FROM local_attachments ORDER BY created_at DESC',
      readsFrom: {},
    ).get();
    return [for (final row in rows) _map(row)];
  }

  /// Wipe every local attachment. Used by [BackupService.wipeLocalData].
  /// Drops both the metadata rows and the binary blobs so the device
  /// really has zero attachments left.
  Future<void> deleteAll() async {
    final rows = await listAll();
    await _db.customStatement('DELETE FROM local_attachments', const []);
    for (final row in rows) {
      await _byteStore.delete(row.relativePath);
    }
  }

  /// Re-insert a [LocalAttachmentRecord] from a JSON-shaped map. Used by
  /// [BackupService.restore] so the on-disk payload round-trips without
  /// reshaping.
  Future<void> insertRaw(Map<String, dynamic> raw) async {
    await _db.customStatement(
      '''
INSERT INTO local_attachments
  (id, book_id, transaction_id, file_name, mime, relative_path, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
      [
        raw['id'] as String,
        raw['bookId'] as String,
        raw['transactionId'] as String,
        raw['fileName'] as String,
        (raw['mimeType'] as String?) ?? 'application/octet-stream',
        raw['relativePath'] as String,
        DateTime.parse(raw['createdAt'] as String)
            .toUtc()
            .millisecondsSinceEpoch,
      ],
    );
  }

  LocalAttachmentRecord _map(QueryRow row) {
    return LocalAttachmentRecord(
      id: row.read<String>('id'),
      bookId: row.read<String>('book_id'),
      transactionId: row.read<String>('transaction_id'),
      fileName: row.read<String>('file_name'),
      mime: row.read<String>('mime'),
      relativePath: row.read<String>('relative_path'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      cloudUploadStatus: AttachmentCloudStatus.parse(
        row.read<String?>('cloud_upload_status'),
      ),
      remoteAttachmentId: row.read<String?>('remote_attachment_id'),
      remoteObjectKey: row.read<String?>('remote_object_key'),
      remoteUploadError: row.read<String?>('remote_upload_error'),
      retryAttemptCount: row.read<int>('retry_attempt_count'),
      nextRetryAt: switch (row.read<int?>('next_retry_at')) {
        final milliseconds? => DateTime.fromMillisecondsSinceEpoch(
            milliseconds,
            isUtc: true,
          ),
        null => null,
      },
      remoteUploadMode: row.read<String?>('remote_upload_mode'),
      remotePartSizeBytes: row.read<int?>('remote_part_size_bytes'),
    );
  }

  Future<void> clearRemoteUploadState(String id) {
    return _db.customStatement(
      '''
UPDATE local_attachments
SET remote_attachment_id = NULL,
    remote_object_key = NULL,
    remote_upload_mode = NULL,
    remote_part_size_bytes = NULL
WHERE id = ?
''',
      [id],
    );
  }
}

/// Abstract byte store so the backup flow can read/write attachment
/// binaries without coupling the data layer to `path_provider`. The
/// default implementation delegates to the filesystem on platforms
/// where binary attachments are supported.
abstract class AttachmentByteStore {
  Future<String> write({required String id, required Uint8List bytes});
  Future<Uint8List?> read(String relativePath);
  Future<int?> length(String relativePath);
  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int end,
  });
  Future<void> delete(String relativePath);
}

/// Filesystem-backed attachment byte store used on Android/iOS/Desktop.
class FileAttachmentByteStore implements AttachmentByteStore {
  Future<dart_io.File> _file(String relativePath) async {
    final dir = await getApplicationDocumentsDirectory();
    return dart_io.File('${dir.path}/$relativePath');
  }

  @override
  Future<String> write({
    required String id,
    required Uint8List bytes,
  }) async {
    final relativePath = 'attachments/$id';
    final file = await _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return relativePath;
  }

  @override
  Future<Uint8List?> read(String relativePath) async {
    final file = await _file(relativePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<int?> length(String relativePath) async {
    final file = await _file(relativePath);
    if (!await file.exists()) return null;
    return file.length();
  }

  @override
  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int end,
  }) async {
    final file = await _file(relativePath);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (start < 0 || end < start || end > length) return null;
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      return await handle.read(end - start);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = await _file(relativePath);
    if (await file.exists()) await file.delete();
  }
}

/// In-memory byte store used in tests and on web where binary
/// attachments are not yet supported. Returns an empty buffer so the
/// rest of the app keeps working without crashing.
class MemoryAttachmentByteStore implements AttachmentByteStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<String> write({
    required String id,
    required Uint8List bytes,
  }) async {
    final relativePath = 'attachments/$id';
    files[relativePath] = bytes;
    return relativePath;
  }

  @override
  Future<Uint8List?> read(String relativePath) async => files[relativePath];

  @override
  Future<int?> length(String relativePath) async => files[relativePath]?.length;

  @override
  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int end,
  }) async {
    final bytes = files[relativePath];
    if (bytes == null || start < 0 || end < start || end > bytes.length) {
      return null;
    }
    return Uint8List.sublistView(bytes, start, end);
  }

  @override
  Future<void> delete(String relativePath) async {
    files.remove(relativePath);
  }
}

/// Platform-default byte store. Delegates to the filesystem-backed
/// implementation; web builds keep using the in-memory variant so the
/// UI does not crash when binary attachments are not supported.
AttachmentByteStore createPlatformAttachmentByteStore() =>
    FileAttachmentByteStore();
