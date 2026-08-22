import 'package:drift/drift.dart';
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
  LocalAttachmentRepository(this._db);

  final AppDatabase _db;

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
    required String bookId,
    required String transactionId,
    required String fileName,
    required String mime,
    required String relativePath,
  }) async {
    final record = LocalAttachmentRecord(
      id: const Uuid().v4(),
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
