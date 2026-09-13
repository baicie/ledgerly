import 'dart:io' as dart_io;

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class LocalAttachmentRecord {
  const LocalAttachmentRecord({
    required this.id,
    required this.bookId,
    required this.transactionId,
    required this.fileName,
    required this.mime,
    required this.relativePath,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String transactionId;
  final String fileName;
  final String mime;
  final String relativePath;
  final DateTime createdAt;
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
  Future<void> deleteBytes(String relativePath) => _byteStore.delete(relativePath);

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
  Future<void> delete(String relativePath) async {
    files.remove(relativePath);
  }
}

/// Platform-default byte store. Delegates to the filesystem-backed
/// implementation; web builds keep using the in-memory variant so the
/// UI does not crash when binary attachments are not supported.
AttachmentByteStore createPlatformAttachmentByteStore() =>
    FileAttachmentByteStore();
