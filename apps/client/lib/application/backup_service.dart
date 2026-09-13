import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/local_attachment_repository.dart';
import '../data/local_budget_repository.dart';
import '../data/local_recurring_repository.dart';
import '../domain/default_categories.dart';
import '../domain/ids.dart' as local_ids;
import 'backup_encryption.dart';
import 'backup_catalog_store.dart';
import 'backup_metadata_store.dart';
import 'merchant_classifier.dart';
import 'merchant_rule_store.dart';

/// Domain object returned by [BackupService.export] and consumed by
/// [BackupService.restore]. Lives entirely in memory; callers turn it
/// into a file via [BackupFilePort].
@immutable
class BackupDocument {
  const BackupDocument({
    required this.summary,
    required this.payload,
    this.bookIds,
    this.attachmentIndex = const [],
    this.attachmentBinaries = const [],
    this.encrypted,
    this.schemaVersion = kFullBackupSchemaVersion,
    this.backupId,
    this.baseBackupId,
    this.deleted = const {},
  });

  /// Counts per entity — surfaced in the restore preview so the user
  /// can sanity-check what they are about to load before confirming.
  final BackupSummary summary;

  /// Stable, versioned JSON payload. The on-disk envelope wraps this in
  /// `{ kind, schemaVersion, exportedAt, deviceId, summary, data }`.
  /// When [encrypted] is present this field holds the **plaintext v2**
  /// payload (used for in-memory restore / restore preview), but the
  /// on-disk container only stores the encrypted ciphertext.
  final Map<String, dynamic> payload;

  /// IDs of the books included in this backup. `null` when the
  /// document was produced by a legacy export (Phase 6) or when every
  /// book is included; callers should treat both cases as "all books".
  /// The field is duplicated inside the envelope for human readability
  /// even though the payload already carries the same information.
  final Set<String>? bookIds;

  /// Index entry per binary attachment (id, relativePath, mime, size,
  /// sha256). Surfaces in the envelope so the restore preview can
  /// show "N attachments · M MB" without unzipping the container.
  /// Empty for legacy v1 documents that did not bundle binaries.
  final List<Map<String, dynamic>> attachmentIndex;

  /// Raw attachment bytes paired with their attachment id. **Not**
  /// serialized into the JSON envelope — the [BackupFilePort] writes
  /// them into a `attachments/<id>.bin` entry inside the zip container.
  /// Empty for documents produced by [BackupDocument.fromEnvelope],
  /// which only sees the manifest.
  final List<AttachmentBinary> attachmentBinaries;

  /// Phase 10: when non-null, this document was wrapped in a password
  /// envelope before being written to disk. The file port will pack
  /// the envelope.json + payload.enc into a single `.enc.zip`; readers
  /// need the password to unwrap and surface the [payload] /
  /// [attachmentBinaries] for restore.
  final EncryptedPayload? encrypted;

  /// Inner payload schema (`1` = Phase 6 JSON, `2` = Phase 9 zip).
  /// Encrypted v3 containers keep this at `2` after unlock; the outer
  /// envelope uses [kEncryptedBackupSchemaVersion] separately.
  final int schemaVersion;

  /// Stable ID written to the envelope. Legacy documents may omit it.
  final String? backupId;

  /// When non-null this document is a delta relative to this full backup.
  final String? baseBackupId;

  /// Entity IDs removed since [baseBackupId], grouped by payload key.
  final Map<String, List<String>> deleted;

  /// Total bytes the bundled attachments consume. Surfaced in the UI so
  /// the user can see how big the backup really is before sharing.
  int get attachmentSizeBytes =>
      attachmentBinaries.fold<int>(0, (sum, b) => sum + b.bytes.length);

  /// True when this document still needs a password before restore.
  bool get isEncrypted => encrypted != null;

  bool get isIncremental => baseBackupId != null;

  Map<String, dynamic> toEnvelope({required String deviceId}) {
    return {
      'kind': 'ledgerly-backup',
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      if (backupId != null) 'backupId': backupId,
      if (baseBackupId != null) 'baseBackupId': baseBackupId,
      if (bookIds != null) 'bookIds': bookIds!.toList()..sort(),
      'summary': summary.toJson(),
      'data': payload,
      if (deleted.isNotEmpty) 'deleted': deleted,
      if (attachmentIndex.isNotEmpty) 'attachmentIndex': attachmentIndex,
    };
  }

  /// Build a [BackupDocument] from a parsed JSON envelope, validating
  /// the discriminator and schema version.
  static BackupDocument fromEnvelope(Map<String, dynamic> envelope) {
    final kind = envelope['kind'];
    final version = envelope['schemaVersion'];
    if (kind != 'ledgerly-backup') {
      throw BackupFormatException(
        '文件不是 Ledgerly 备份 (kind=$kind)',
      );
    }
    if (version is! int ||
        version > kBackupSchemaVersion ||
        version < kMinReadableBackupSchemaVersion) {
      throw BackupFormatException(
        '备份 schema 版本不匹配：当前 $kBackupSchemaVersion，文件 $version',
      );
    }
    final summaryJson = envelope['summary'];
    if (summaryJson is! Map) {
      throw const BackupFormatException('备份 summary 缺失');
    }
    final data = envelope['data'];
    if (data is! Map) {
      throw const BackupFormatException('备份 data 缺失');
    }
    final rawBookIds = envelope['bookIds'];
    final bookIds =
        rawBookIds is List ? rawBookIds.whereType<String>().toSet() : null;
    final rawIndex = envelope['attachmentIndex'];
    final attachmentIndex = rawIndex is List
        ? rawIndex
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];
    final rawDeleted = envelope['deleted'];
    final deleted = <String, List<String>>{};
    if (rawDeleted is Map) {
      for (final entry in rawDeleted.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is List) {
          deleted[key] = value.whereType<String>().toList();
        }
      }
    }
    return BackupDocument(
      summary: BackupSummary.fromJson(
        Map<String, dynamic>.from(summaryJson),
      ),
      payload: Map<String, dynamic>.from(data),
      bookIds: bookIds,
      attachmentIndex: attachmentIndex,
      schemaVersion: version,
      backupId: envelope['backupId'] as String?,
      baseBackupId: envelope['baseBackupId'] as String?,
      deleted: deleted,
    );
  }

  /// Convenience for callers (and tests) that already have the
  /// attachment binaries on hand. Produces a new document with the
  /// binaries attached; the input is left untouched.
  BackupDocument withBinaries(List<AttachmentBinary> binaries) {
    return BackupDocument(
      summary: summary,
      payload: payload,
      bookIds: bookIds,
      attachmentIndex: attachmentIndex,
      attachmentBinaries: List.unmodifiable(binaries),
      encrypted: encrypted,
      schemaVersion: schemaVersion,
      backupId: backupId,
      baseBackupId: baseBackupId,
      deleted: deleted,
    );
  }

  /// Returns a copy of this document with the supplied [encrypted]
  /// payload attached. The plaintext payload / binaries stay on the
  /// in-memory document so the restore preview can still render them
  /// before the user types a password.
  BackupDocument withEncryption(EncryptedPayload encrypted) {
    return BackupDocument(
      summary: summary,
      payload: payload,
      bookIds: bookIds,
      attachmentIndex: attachmentIndex,
      attachmentBinaries: attachmentBinaries,
      encrypted: encrypted,
      schemaVersion: schemaVersion,
      backupId: backupId,
      baseBackupId: baseBackupId,
      deleted: deleted,
    );
  }
}

/// Pairs an attachment id with the raw bytes read from the device
/// store. Carried alongside [BackupDocument.attachmentIndex] so the
/// [BackupFilePort] can write the binaries into the zip container
/// without re-reading the filesystem.
@immutable
class AttachmentBinary {
  const AttachmentBinary({required this.id, required this.bytes});

  final String id;
  final Uint8List bytes;
}

/// Snapshot of counts per entity. Surfaced in the restore dialog.
@immutable
class BackupSummary {
  const BackupSummary({
    required this.books,
    required this.accounts,
    required this.transactions,
    required this.transactionEntries,
    required this.recurringRules,
    required this.budgets,
    required this.attachments,
    required this.merchantRules,
  });

  final int books;
  final int accounts;
  final int transactions;
  final int transactionEntries;
  final int recurringRules;
  final int budgets;
  final int attachments;
  final int merchantRules;

  int get total =>
      books +
      accounts +
      transactions +
      transactionEntries +
      recurringRules +
      budgets +
      attachments +
      merchantRules;

  Map<String, dynamic> toJson() => {
        'books': books,
        'accounts': accounts,
        'transactions': transactions,
        'transactionEntries': transactionEntries,
        'recurringRules': recurringRules,
        'budgets': budgets,
        'attachments': attachments,
        'merchantRules': merchantRules,
      };

  static BackupSummary fromJson(Map<String, dynamic> json) => BackupSummary(
        books: (json['books'] as num?)?.toInt() ?? 0,
        accounts: (json['accounts'] as num?)?.toInt() ?? 0,
        transactions: (json['transactions'] as num?)?.toInt() ?? 0,
        transactionEntries: (json['transactionEntries'] as num?)?.toInt() ?? 0,
        recurringRules: (json['recurringRules'] as num?)?.toInt() ?? 0,
        budgets: (json['budgets'] as num?)?.toInt() ?? 0,
        attachments: (json['attachments'] as num?)?.toInt() ?? 0,
        merchantRules: (json['merchantRules'] as num?)?.toInt() ?? 0,
      );
}

/// Restore semantics shown in the data-governance preview.
enum BackupRestoreMode { replace, merge }

/// Summary of a merge-restore operation.
@immutable
class BackupMergeResult {
  const BackupMergeResult({
    required this.addedBooks,
    required this.replacedBooks,
    required this.skippedBooks,
    required this.addedAccounts,
    required this.addedTransactions,
    required this.addedRecurringRules,
    required this.addedBudgets,
    required this.addedAttachments,
    required this.addedMerchantRules,
  });

  final int addedBooks;
  final int replacedBooks;
  final int skippedBooks;
  final int addedAccounts;
  final int addedTransactions;
  final int addedRecurringRules;
  final int addedBudgets;
  final int addedAttachments;
  final int addedMerchantRules;

  int get mergedBooks => addedBooks + replacedBooks;

  bool get changed =>
      mergedBooks > 0 || addedMerchantRules > 0 || addedAttachments > 0;
}

@immutable
class BackupCleanupResult {
  const BackupCleanupResult({
    required this.deletedCount,
    required this.freedBytes,
    required this.failedCount,
  });

  final int deletedCount;
  final int freedBytes;
  final int failedCount;
}

@immutable
class BackupConsolidationResult {
  const BackupConsolidationResult({
    required this.path,
    required this.backupId,
    required this.sizeBytes,
  });

  final String path;
  final String backupId;
  final int sizeBytes;
}

@immutable
class BackupRecoveryDrillResult {
  const BackupRecoveryDrillResult({
    required this.path,
    required this.backupId,
    required this.encrypted,
    required this.incremental,
    required this.summary,
    required this.bundledAttachmentCount,
    required this.attachmentSizeBytes,
  });

  final String path;
  final String? backupId;
  final bool encrypted;
  final bool incremental;
  final BackupSummary summary;
  final int bundledAttachmentCount;
  final int attachmentSizeBytes;
}

enum BackupVerificationStatus { healthy, missing, corrupted }

@immutable
class BackupVerificationEntry {
  const BackupVerificationEntry({
    required this.artifact,
    required this.status,
    this.actualSha256,
    this.error,
  });

  final BackupArtifact artifact;
  final BackupVerificationStatus status;
  final String? actualSha256;
  final String? error;
}

@immutable
class BackupVerificationReport {
  const BackupVerificationReport(this.entries);

  final List<BackupVerificationEntry> entries;

  int get healthyCount => entries
      .where((entry) => entry.status == BackupVerificationStatus.healthy)
      .length;

  int get missingCount => entries
      .where((entry) => entry.status == BackupVerificationStatus.missing)
      .length;

  int get corruptedCount => entries
      .where((entry) => entry.status == BackupVerificationStatus.corrupted)
      .length;
}

/// Thrown when a backup file is structurally invalid.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Thrown when deleting a catalog artifact would break the active backup
/// chain or another incremental backup that still depends on it.
class BackupArtifactProtectedException implements Exception {
  const BackupArtifactProtectedException(this.message);

  final String message;

  @override
  String toString() => 'BackupArtifactProtectedException: $message';
}

/// Full backup payload version. Phase 9 introduced the zip container
/// and bundled attachment binaries at version `2`.
const int kFullBackupSchemaVersion = 2;

/// Incremental payload version. Phase 14 adds `baseBackupId` and
/// `deleted`, so older clients must refuse the file rather than
/// treating a delta as a complete snapshot.
const int kIncrementalBackupSchemaVersion = 3;

/// Highest on-disk schema version this client can restore.
const int kBackupSchemaVersion = kIncrementalBackupSchemaVersion;

/// Current outer-container schema version. Bumped when the on-disk
/// envelope changes shape: `3` introduced AES-256-GCM password
/// encryption (Phase 10). Plaintext v2 backups are still written by
/// this build; only the *encrypted* branch hits v3.
const int kEncryptedBackupSchemaVersion = 3;

/// Lowest schema version the current code can still restore. Older
/// files (v1) load but the restore preview warns the user that
/// attachment binaries were not bundled in that revision.
const int kMinReadableBackupSchemaVersion = 1;

const List<String> _deltaEntityKeys = [
  'books',
  'accounts',
  'transactions',
  'transactionEntries',
  'recurringRules',
  'budgets',
  'attachments',
  'merchantRules',
];

/// Snapshot of all user-owned local data. The service intentionally
/// avoids touching sync state (cursor, lastError, remoteBookId) since
/// those are tied to a specific device + remote endpoint.
class BackupService {
  BackupService({
    required AppDatabase database,
    required LocalRecurringRepository recurring,
    required LocalBudgetRepository budgets,
    required LocalAttachmentRepository attachments,
    required MerchantRuleStore merchantRules,
    required BackupFilePort filePort,
    required Future<String> Function() deviceIdLoader,
    BackupMetadataStore? metadata,
    BackupEncryption? encryption,
    BackupCatalogStore? catalog,
  })  : _db = database,
        _recurring = recurring,
        _budgets = budgets,
        _attachments = attachments,
        _merchantRules = merchantRules,
        _files = filePort,
        _deviceIdLoader = deviceIdLoader,
        _metadata = metadata ?? BackupMetadataStore(),
        _encryption = encryption ?? BackupEncryption(),
        _catalog = catalog ?? BackupCatalogStore();

  final AppDatabase _db;
  final LocalRecurringRepository _recurring;
  final LocalBudgetRepository _budgets;
  final LocalAttachmentRepository _attachments;
  final MerchantRuleStore _merchantRules;
  final BackupFilePort _files;
  final Future<String> Function() _deviceIdLoader;
  final BackupMetadataStore _metadata;
  final BackupEncryption _encryption;
  final BackupCatalogStore _catalog;

  /// Read every entity into a memory [BackupDocument]. The document holds
  /// raw row payloads — file I/O is delegated to [BackupFilePort].
  ///
  /// Pass [bookIds] to scope the export to a subset of books. `null` or
  /// an empty set means "every book" — the default Phase 6 behaviour.
  /// The selection cascades through accounts → transactions → entries
  /// and the per-book tables (recurring, budgets, attachments).
  /// Merchant rules are global and always included — they don't belong
  /// to any single book.
  ///
  /// Pass [password] (≥ 8 characters) to wrap the v2 zip bytes in a
  /// password-encrypted v3 envelope before returning. The plaintext
  /// payload + attachment binaries stay on the returned document so
  /// the restore preview can still render summary counts without
  /// requiring the user to retype the password.
  Future<BackupDocument> export({
    Set<String>? bookIds,
    String? password,
  }) async {
    final hasFilter = bookIds != null && bookIds.isNotEmpty;

    Future<List<T>> scoped<T>(
      Future<List<T>> Function() fetchAll,
      bool Function(T) belongsToSelection,
    ) async {
      if (!hasFilter) return fetchAll();
      final all = await fetchAll();
      return all.where(belongsToSelection).toList();
    }

    final books = await scoped<Book>(
      () => _db.select(_db.books).get(),
      (b) => bookIds!.contains(b.id),
    );
    final scopedBookIds = books.map((b) => b.id).toSet();

    final accounts = await scoped<Account>(
      () => _db.select(_db.accounts).get(),
      (a) => scopedBookIds.contains(a.bookId),
    );

    final transactions = await scoped<Transaction>(
      () => _db.select(_db.transactions).get(),
      (t) => scopedBookIds.contains(t.bookId),
    );
    final scopedTxIds = transactions.map((t) => t.id).toSet();

    final entries = await scoped<TransactionEntry>(
      () => _db.select(_db.transactionEntries).get(),
      (e) => scopedTxIds.contains(e.transactionId),
    );

    final recurring = await scoped<LocalRecurringRule>(
      () => _recurring.listAll(),
      (r) => scopedBookIds.contains(r.bookId),
    );
    final budgets = await scoped<LocalBudgetRecord>(
      () => _budgets.listAll(),
      (b) => scopedBookIds.contains(b.bookId),
    );
    final attachments = await scoped<LocalAttachmentRecord>(
      () => _attachments.listAll(),
      (a) => scopedBookIds.contains(a.bookId),
    );

    // Read attachment binaries off the device's byte store so the
    // resulting zip container is a self-contained snapshot. Orphan
    // attachments (metadata present, bytes missing) are dropped from
    // the bundle but kept in the payload so the user can still see
    // them after restore — the UI surfaces "binary missing" hints.
    final attachmentBinaries = <AttachmentBinary>[];
    final attachmentIndex = <Map<String, dynamic>>[];
    for (final meta in attachments) {
      final bytes = await _attachments.readBytes(meta.relativePath);
      if (bytes == null) continue;
      final digest = sha256.convert(bytes).toString();
      attachmentBinaries.add(AttachmentBinary(id: meta.id, bytes: bytes));
      attachmentIndex.add({
        'id': meta.id,
        'relativePath': meta.relativePath,
        'fileName': meta.fileName,
        'mime': meta.mime,
        'size': bytes.length,
        'sha256': digest,
      });
    }

    final merchantRules = await _merchantRules.load();

    // Flat lists per table keep the schema easy to inspect with `jq`
    // and avoid nesting that future readers would have to walk.
    final payload = <String, dynamic>{
      'books': books.map((row) => _bookToJson(row)).toList(),
      'accounts': accounts.map((row) => _accountToJson(row)).toList(),
      'transactions':
          transactions.map((row) => _transactionToJson(row)).toList(),
      'transactionEntries':
          entries.map((row) => _transactionEntryToJson(row)).toList(),
      'recurringRules': recurring.map((row) => _recurringToJson(row)).toList(),
      'budgets': budgets.map((row) => _budgetToJson(row)).toList(),
      'attachments': attachments.map((row) => _attachmentToJson(row)).toList(),
      'merchantRules':
          merchantRules.map((rule) => _merchantRuleToJson(rule)).toList(),
    };

    final summary = BackupSummary(
      books: books.length,
      accounts: accounts.length,
      transactions: transactions.length,
      transactionEntries: entries.length,
      recurringRules: recurring.length,
      budgets: budgets.length,
      attachments: attachments.length,
      merchantRules: merchantRules.length,
    );
    var document = BackupDocument(
      summary: summary,
      payload: payload,
      bookIds: hasFilter ? scopedBookIds : null,
      attachmentIndex: attachmentIndex,
      attachmentBinaries: attachmentBinaries,
      backupId: const Uuid().v4(),
    );

    // Phase 10: if the caller supplied a password, seal the v2
    // payload into a password-encrypted envelope before returning.
    // The plaintext payload / binaries stay on the document so the
    // in-memory restore preview keeps working without retyping the
    // password.
    if (password != null && password.isNotEmpty) {
      final deviceId = await _deviceIdLoader();
      document = await _encryptDocument(
        document,
        password: password,
        deviceId: deviceId,
      );
    }

    return document;
  }

  /// Replace the entire local dataset with the contents of [document].
  ///
  /// Runs inside a single Drift `transaction {}` so a partial failure
  /// rolls back instead of leaving a half-empty database. Pending
  /// sync mutations and conflict markers are intentionally not restored
  /// — they belong to the previous device's sync session.
  ///
  /// Pass [password] to unwrap a v3 password-encrypted document. When
  /// the document was encrypted with a different password (or has been
  /// tampered with) [BackupPasswordException] / [BackupTamperedException]
  /// bubble up; the caller should surface them as a UI error rather
  /// than leaving the database half-wiped.
  Future<void> restore(BackupDocument document, {String? password}) async {
    final unlocked = document.encrypted != null
        ? await _unwrapEncrypted(document, password: password)
        : document;
    final resolved = await _materializeIncremental(unlocked);
    final data = resolved.payload;
    final books = _asList(data['books'], 'books');
    final accounts = _asList(data['accounts'], 'accounts');
    final transactions = _asList(data['transactions'], 'transactions');
    final entries = _asList(data['transactionEntries'], 'transactionEntries');
    final recurringRules = _asList(data['recurringRules'], 'recurringRules');
    final budgets = _asList(data['budgets'], 'budgets');
    final attachments = _asList(data['attachments'], 'attachments');
    final merchantRules = _asList(data['merchantRules'], 'merchantRules');

    await _db.transaction(() async {
      // Wipe in FK-safe order: leaves first, roots last.
      await _db.delete(_db.transactionEntries).go();
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.books).go();

      for (final raw in books) {
        await _db.into(_db.books).insert(
              BooksCompanion.insert(
                id: raw['id'] as String,
                name: raw['name'] as String,
                currencyCode: raw['currencyCode'] as String,
                createdAt: DateTime.parse(raw['createdAt'] as String).toLocal(),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      for (final raw in accounts) {
        await _db.into(_db.accounts).insert(
              AccountsCompanion.insert(
                id: raw['id'] as String,
                bookId: raw['bookId'] as String,
                name: raw['name'] as String,
                type: raw['type'] as String,
                currencyCode: raw['currencyCode'] as String? ?? 'CNY',
                parentAccountId: Value(raw['parentAccountId'] as String?),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      for (final raw in transactions) {
        await _db.into(_db.transactions).insert(
              TransactionsCompanion.insert(
                id: raw['id'] as String,
                bookId: raw['bookId'] as String,
                occurredAt:
                    DateTime.parse(raw['occurredAt'] as String).toLocal(),
                description: Value(raw['description'] as String?),
                version: Value((raw['version'] as num?)?.toInt() ?? 1),
                createdAt: DateTime.parse(raw['createdAt'] as String).toLocal(),
                deletedAt:
                    Value(_parseNullableDate(raw['deletedAt'] as String?)),
                source: Value(raw['source'] as String?),
                sourceEventFingerprint:
                    Value(raw['sourceEventFingerprint'] as String?),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      for (final raw in entries) {
        await _db.into(_db.transactionEntries).insert(
              TransactionEntriesCompanion.insert(
                id: raw['id'] as String,
                transactionId: raw['transactionId'] as String,
                accountId: raw['accountId'] as String,
                amountMinor: raw['amountMinor'] as String,
                currencyCode: raw['currencyCode'] as String? ?? 'CNY',
                entryIndex: (raw['entryIndex'] as num).toInt(),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    });

    // Non-Drift stores are restored outside the transaction because they
    // live in SharedPreferences and have no FK relationship.
    await _restoreRecurring(recurringRules);
    await _restoreBudgets(budgets);
    await _restoreAttachments(attachments);
    await _restoreMerchantRules(merchantRules);

    // Attachment binaries are written after metadata so the relative
    // path the metadata points at is the one we just produced. Binaries
    // outside the attachmentIndex are ignored — the metadata alone is
    // enough to surface "binary missing" in the UI.
    for (final binary in resolved.attachmentBinaries) {
      await _attachments.writeBytes(id: binary.id, bytes: binary.bytes);
    }
  }

  /// Merge books from [document] into the current local database.
  ///
  /// Unlike [restore], this never wipes current books. A backup book is
  /// added when its ID is new; an untouched default placeholder with the
  /// same ID is replaced; a book that already contains business data is
  /// skipped as a whole. Database writes are atomic.
  Future<BackupMergeResult> merge(
    BackupDocument document, {
    String? password,
  }) async {
    final unlocked = document.encrypted != null
        ? await _unwrapEncrypted(document, password: password)
        : document;
    final resolved = await _materializeIncremental(unlocked);
    final data = resolved.payload;
    final books = _asList(data['books'], 'books');
    final accounts = _asList(data['accounts'], 'accounts');
    final transactions = _asList(data['transactions'], 'transactions');
    final entries = _asList(data['transactionEntries'], 'transactionEntries');
    final recurringRules = _asList(data['recurringRules'], 'recurringRules');
    final budgets = _asList(data['budgets'], 'budgets');
    final attachments = _asList(data['attachments'], 'attachments');
    final merchantRules = _asList(data['merchantRules'], 'merchantRules');

    final backupBooks = <String, Map<String, dynamic>>{};
    for (final raw in books) {
      final id = raw['id'];
      if (id is! String || id.isEmpty) {
        throw const BackupFormatException('备份中存在缺少 id 的账本');
      }
      if (backupBooks.containsKey(id)) {
        throw BackupFormatException('备份中存在重复账本：$id');
      }
      backupBooks[id] = raw;
    }

    final existingBookIds = {
      for (final book in await _db.select(_db.books).get()) book.id,
    };
    final addedBookIds = <String>{};
    final replacedBookIds = <String>{};
    final skippedBookIds = <String>{};
    for (final bookId in backupBooks.keys) {
      if (!existingBookIds.contains(bookId)) {
        addedBookIds.add(bookId);
      } else if (await _isReplaceablePlaceholderBook(bookId)) {
        replacedBookIds.add(bookId);
      } else {
        skippedBookIds.add(bookId);
      }
    }
    final selectedBookIds = {...addedBookIds, ...replacedBookIds};

    final selectedAccounts = accounts
        .where((raw) => selectedBookIds.contains(raw['bookId']))
        .toList();
    final selectedTransactions = transactions
        .where((raw) => selectedBookIds.contains(raw['bookId']))
        .toList();
    final selectedTransactionIds = {
      for (final raw in selectedTransactions)
        if (raw['id'] is String) raw['id'] as String,
    };
    final selectedEntries = entries
        .where(
          (raw) => selectedTransactionIds.contains(raw['transactionId']),
        )
        .toList();
    final selectedRecurring = recurringRules
        .where((raw) => selectedBookIds.contains(raw['bookId']))
        .toList();
    final selectedBudgets = budgets
        .where((raw) => selectedBookIds.contains(raw['bookId']))
        .toList();
    final selectedAttachments = attachments
        .where((raw) => selectedBookIds.contains(raw['bookId']))
        .toList();
    final selectedAttachmentIds = {
      for (final raw in selectedAttachments)
        if (raw['id'] is String) raw['id'] as String,
    };

    final existingRules = await _merchantRules.load();
    final mergedRules = <String, MerchantRule>{
      for (final rule in existingRules)
        if (rule.id != null) rule.id!: rule,
    };
    var addedMerchantRules = 0;
    for (final raw in merchantRules) {
      final rule = _merchantRuleFromJson(raw);
      final ruleId = rule?.id;
      if (rule == null || ruleId == null || mergedRules.containsKey(ruleId)) {
        continue;
      }
      mergedRules[ruleId] = rule;
      addedMerchantRules++;
    }
    if (addedMerchantRules > 0) {
      await _merchantRules.save(mergedRules.values.toList());
    }

    final deviceId = await _deviceIdLoader();
    try {
      await _db.transaction(() async {
        for (final bookId in replacedBookIds) {
          await (_db.delete(_db.accounts)
                ..where((account) => account.bookId.equals(bookId)))
              .go();
          await (_db.delete(_db.syncStates)
                ..where((state) => state.bookId.equals(bookId)))
              .go();
          await (_db.delete(_db.books)..where((book) => book.id.equals(bookId)))
              .go();
        }

        for (final raw in books) {
          if (!selectedBookIds.contains(raw['id'])) continue;
          await _db.into(_db.books).insert(
                BooksCompanion.insert(
                  id: raw['id'] as String,
                  name: raw['name'] as String,
                  currencyCode: raw['currencyCode'] as String,
                  createdAt:
                      DateTime.parse(raw['createdAt'] as String).toLocal(),
                ),
              );
        }
        for (final raw in selectedAccounts) {
          await _db.into(_db.accounts).insert(
                AccountsCompanion.insert(
                  id: raw['id'] as String,
                  bookId: raw['bookId'] as String,
                  name: raw['name'] as String,
                  type: raw['type'] as String,
                  currencyCode: raw['currencyCode'] as String? ?? 'CNY',
                  parentAccountId: Value(raw['parentAccountId'] as String?),
                ),
              );
        }
        for (final raw in selectedTransactions) {
          await _db.into(_db.transactions).insert(
                TransactionsCompanion.insert(
                  id: raw['id'] as String,
                  bookId: raw['bookId'] as String,
                  occurredAt:
                      DateTime.parse(raw['occurredAt'] as String).toLocal(),
                  description: Value(raw['description'] as String?),
                  version: Value((raw['version'] as num?)?.toInt() ?? 1),
                  createdAt:
                      DateTime.parse(raw['createdAt'] as String).toLocal(),
                  deletedAt:
                      Value(_parseNullableDate(raw['deletedAt'] as String?)),
                  source: Value(raw['source'] as String?),
                  sourceEventFingerprint:
                      Value(raw['sourceEventFingerprint'] as String?),
                ),
              );
        }
        for (final raw in selectedEntries) {
          await _db.into(_db.transactionEntries).insert(
                TransactionEntriesCompanion.insert(
                  id: raw['id'] as String,
                  transactionId: raw['transactionId'] as String,
                  accountId: raw['accountId'] as String,
                  amountMinor: raw['amountMinor'] as String,
                  currencyCode: raw['currencyCode'] as String? ?? 'CNY',
                  entryIndex: (raw['entryIndex'] as num).toInt(),
                ),
              );
        }
        for (final raw in selectedRecurring) {
          await _recurring.insertRaw(raw);
        }
        for (final raw in selectedBudgets) {
          await _budgets.insertRaw(raw);
        }
        for (final raw in selectedAttachments) {
          await _attachments.insertRaw(raw);
        }
        for (final bookId in selectedBookIds) {
          await _db.into(_db.syncStates).insert(
                SyncStatesCompanion.insert(
                  bookId: bookId,
                  deviceId: deviceId,
                  updatedAt: DateTime.now().toUtc(),
                ),
              );
        }
      });
    } catch (error) {
      if (addedMerchantRules > 0) {
        await _merchantRules.save(existingRules);
      }
      rethrow;
    }

    for (final binary in resolved.attachmentBinaries) {
      if (!selectedAttachmentIds.contains(binary.id)) continue;
      await _attachments.writeBytes(id: binary.id, bytes: binary.bytes);
    }

    return BackupMergeResult(
      addedBooks: addedBookIds.length,
      replacedBooks: replacedBookIds.length,
      skippedBooks: skippedBookIds.length,
      addedAccounts: selectedAccounts.length,
      addedTransactions: selectedTransactions.length,
      addedRecurringRules: selectedRecurring.length,
      addedBudgets: selectedBudgets.length,
      addedAttachments: selectedAttachments.length,
      addedMerchantRules: addedMerchantRules,
    );
  }

  /// Delete every user-owned row. Pending sync mutations and conflict
  /// markers are cleared too so the local database is truly empty.
  Future<void> wipeLocalData() async {
    await _db.transaction(() async {
      await _db.delete(_db.transactionEntries).go();
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.books).go();
      await _db.delete(_db.pendingMutations).go();
      await _db.delete(_db.syncConflicts).go();
      await _db.delete(_db.syncStates).go();
    });
    await _recurring.deleteAll();
    await _budgets.deleteAll();
    await _attachments.deleteAll();
    await _merchantRules.clear();

    // Drop other app-owned SharedPreferences keys that we shouldn't carry
    // across a wipe (selected book, sync state hints).
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_book_id');
    await prefs.remove('ledgerly.sync.last_endpoint');

    // Reset the persisted backup timestamp so the data governance page
    // doesn't keep advertising a backup the user has explicitly thrown
    // away.
    await _metadata.reset();
  }

  // -- Convenience for the UI layer -------------------------------------

  /// Build a [BackupDocument] from the live database, then persist it
  /// via the [BackupFilePort]. Returns the destination identifier
  /// produced by the port so the caller can hand it to the user (e.g.
  /// to show in a snackbar or share sheet).
  ///
  /// When [bookIds] is provided (non-null, non-empty) the export is
  /// scoped to that subset of books. See [export] for the cascade
  /// rules.
  ///
  /// When [password] is provided (≥ 8 chars) the snapshot is wrapped
  /// in a v3 password-encrypted envelope before being written; the
  /// resulting file uses the `.enc.zip` extension so the user can
  /// tell at a glance that it is password-protected.
  ///
  /// On success, also records the backup timestamp through the
  /// [BackupMetadataStore] so the data governance page can render
  /// "上次备份: X 天前" across app restarts.
  Future<String> exportToFile({
    Set<String>? bookIds,
    String? password,
    bool incremental = false,
    bool automatic = false,
  }) async {
    var document = await export(bookIds: bookIds, password: password);
    final snapshotAttachmentCount = document.summary.attachments;
    final snapshotAttachmentSizeBytes = document.attachmentSizeBytes;
    var wroteIncremental = false;
    String? baseBackupId;
    String? baseBackupPath;
    if (incremental && (password == null || password.isEmpty)) {
      try {
        final base = await _loadIncrementalBase();
        if (base != null) {
          document = _buildIncremental(current: document, base: base);
          wroteIncremental = true;
          baseBackupId = base.backupId;
          baseBackupPath = (await _metadata.read()).baseBackupPath;
        }
      } catch (_) {
        // A malformed or inaccessible base must never block a normal
        // full backup. Reuse the current full document unchanged.
      }
    }
    final deviceId = await _deviceIdLoader();
    final path = await _files.writeBackup(document, deviceId: deviceId);
    final completedAt = DateTime.now().toUtc();
    if (wroteIncremental &&
        baseBackupId != null &&
        baseBackupPath != null &&
        document.backupId != null) {
      await _metadata.recordIncremental(
        path: path,
        at: completedAt,
        backupId: document.backupId!,
        baseBackupId: baseBackupId,
        baseBackupPath: baseBackupPath,
        attachmentCount: snapshotAttachmentCount,
        attachmentSizeBytes: snapshotAttachmentSizeBytes,
      );
    } else {
      await _metadata.record(
        path: path,
        at: completedAt,
        backupId: document.backupId,
        attachmentCount: document.attachmentBinaries.length,
        attachmentSizeBytes: document.attachmentSizeBytes,
        encrypted: document.encrypted != null,
      );
    }
    await _recordCatalogArtifact(
      document: document,
      path: path,
      createdAt: completedAt,
      source: automatic
          ? BackupArtifactSource.automatic
          : BackupArtifactSource.manual,
    );
    return path;
  }

  /// Let the user pick a backup file, parse it, and return the
  /// resulting [BackupDocument]. Returns `null` when the user cancels.
  ///
  /// Pass [password] when the user is restoring from an `.enc.zip`
  /// (Phase 10 schema v3). Wrong / missing password surfaces as
  /// [BackupPasswordException]; tampering surfaces as
  /// [BackupTamperedException] — both are subtypes of
  /// [BackupFormatException] so the existing UI handler picks them up.
  Future<BackupDocument?> pickAndRead({String? password}) async {
    final source = await _files.pickBackupSource();
    if (source == null) return null;
    final document = await _files.readBackup(source, password: password);
    if (document.encrypted == null) {
      return _materializeIncremental(document);
    }
    if (password == null || password.isEmpty) return document;
    final unlocked = await _unwrapEncrypted(document, password: password);
    return _materializeIncremental(unlocked);
  }

  /// Decrypt a v3 document and return the inner v2 snapshot. Used by
  /// the restore UI after the user types the backup password.
  Future<BackupDocument> unlockEncrypted(
    BackupDocument document, {
    required String password,
  }) async {
    final unlocked = await _unwrapEncrypted(document, password: password);
    return _materializeIncremental(unlocked);
  }

  /// Snapshot the live database into a safety backup *before* running
  /// [restore]. Returns the safety destination so the UI can surface
  /// it to the user. The caller still owns calling [restore] with the
  /// user-chosen [document].
  Future<String> writeSafetyBackup() async {
    final current = await export();
    final deviceId = await _deviceIdLoader();
    final path = await _files.writePreRestoreSafetyBackup(
      current,
      deviceId: deviceId,
    );
    await _recordCatalogArtifact(
      document: current,
      path: path,
      createdAt: DateTime.now().toUtc(),
      source: BackupArtifactSource.safety,
    );
    return path;
  }

  /// Materialize the latest incremental backup into a new standalone full
  /// backup. Returns `null` when the latest backup is already full/absent.
  ///
  /// Pass [password] to write a password-encrypted `.enc.zip`; leaving it
  /// null or empty keeps the Phase 16 plaintext `.ledgerly.zip` behavior.
  /// Encrypted portable backups are not used as the incremental base.
  Future<BackupConsolidationResult?> consolidateLatest({
    String? password,
  }) async {
    final metadata = await _metadata.read();
    final source = metadata.lastBackupPath;
    if (source == null) return null;

    final latest = await _files.readBackup(source);
    if (!latest.isIncremental || latest.isEncrypted) return null;
    final materialized = await _materializeIncremental(latest);
    final backupId = const Uuid().v4();
    var full = BackupDocument(
      summary: materialized.summary,
      payload: materialized.payload,
      bookIds: materialized.bookIds,
      attachmentIndex: materialized.attachmentIndex,
      attachmentBinaries: materialized.attachmentBinaries,
      schemaVersion: kFullBackupSchemaVersion,
      backupId: backupId,
    );

    final deviceId = await _deviceIdLoader();
    if (password != null && password.isNotEmpty) {
      full = await _encryptDocument(
        full,
        password: password,
        deviceId: deviceId,
      );
    }
    final path = await _files.writeBackup(full, deviceId: deviceId);
    final createdAt = DateTime.now().toUtc();
    final size = await _files.fileSize(path);
    await _metadata.record(
      path: path,
      at: createdAt,
      backupId: backupId,
      attachmentCount: full.summary.attachments,
      attachmentSizeBytes: full.attachmentSizeBytes,
      encrypted: full.encrypted != null,
    );
    await _recordCatalogArtifact(
      document: full,
      path: path,
      createdAt: createdAt,
      source: BackupArtifactSource.manual,
    );
    return BackupConsolidationResult(
      path: path,
      backupId: backupId,
      sizeBytes: size,
    );
  }

  /// Remove old automatic and safety backups while preserving every manual
  /// export plus the current incremental base and most recent backup.
  Future<BackupCleanupResult> cleanupBackups({
    int keepAutomatic = 3,
    int keepSafety = 1,
  }) async {
    final artifacts = await _catalog.read();
    final metadata = await _metadata.read();
    final protectedPaths = <String>{
      if (metadata.lastBackupPath != null) metadata.lastBackupPath!,
      if (metadata.baseBackupPath != null) metadata.baseBackupPath!,
    };

    int firstAutomaticToKeep = keepAutomatic < 0 ? 0 : keepAutomatic;
    int firstSafetyToKeep = keepSafety < 0 ? 0 : keepSafety;
    final keepPaths = <String>{...protectedPaths};
    for (final artifact in artifacts) {
      if (artifact.source == BackupArtifactSource.manual) {
        keepPaths.add(artifact.path);
      } else if (artifact.source == BackupArtifactSource.automatic &&
          firstAutomaticToKeep > 0) {
        keepPaths.add(artifact.path);
        firstAutomaticToKeep--;
      } else if (artifact.source == BackupArtifactSource.safety &&
          firstSafetyToKeep > 0) {
        keepPaths.add(artifact.path);
        firstSafetyToKeep--;
      }
    }

    var deletedCount = 0;
    var freedBytes = 0;
    var failedCount = 0;
    for (final artifact in artifacts) {
      if (keepPaths.contains(artifact.path)) continue;
      try {
        await _files.deleteBackup(artifact.path);
        await _catalog.removeByPath(artifact.path);
        deletedCount++;
        freedBytes += artifact.sizeBytes;
      } catch (_) {
        failedCount++;
      }
    }
    return BackupCleanupResult(
      deletedCount: deletedCount,
      freedBytes: freedBytes,
      failedCount: failedCount,
    );
  }

  /// Verify catalog artifacts without modifying or deleting backup files.
  /// Legacy records without a checksum are backfilled on first inspection.
  Future<BackupVerificationReport> verifyBackups() async {
    final artifacts = await _catalog.read();
    final entries = <BackupVerificationEntry>[];
    for (final artifact in artifacts) {
      final actualSha256 = await _files.fileSha256(artifact.path);
      if (actualSha256 == null) {
        entries.add(
          BackupVerificationEntry(
            artifact: artifact,
            status: BackupVerificationStatus.missing,
          ),
        );
        continue;
      }

      if (artifact.sha256 == null) {
        await _catalog.upsert(
          artifact.copyWith(
            sizeBytes: await _files.fileSize(artifact.path),
            sha256: actualSha256,
          ),
        );
      } else if (artifact.sha256 != actualSha256) {
        entries.add(
          BackupVerificationEntry(
            artifact: artifact,
            status: BackupVerificationStatus.corrupted,
            actualSha256: actualSha256,
            error: 'SHA-256 mismatch',
          ),
        );
        continue;
      }

      try {
        final document = await _files.readBackup(artifact.path);
        await _backfillArtifactBase(artifact, document);
        entries.add(
          BackupVerificationEntry(
            artifact: artifact,
            status: BackupVerificationStatus.healthy,
            actualSha256: actualSha256,
          ),
        );
      } catch (error) {
        entries.add(
          BackupVerificationEntry(
            artifact: artifact,
            status: BackupVerificationStatus.corrupted,
            actualSha256: actualSha256,
            error: '$error',
          ),
        );
      }
    }
    return BackupVerificationReport(entries);
  }

  /// Perform a non-destructive recovery drill against the latest backup.
  ///
  /// Unlike [verifyBackups], which only proves that each container can be
  /// parsed, this path materializes a plaintext incremental chain against
  /// its base and decrypts an encrypted backup when [password] is supplied.
  /// It then validates row IDs, summary counts, and attachment hashes
  /// without writing to the live database.
  Future<BackupRecoveryDrillResult> runRecoveryDrill({
    String? password,
  }) async {
    final metadata = await _metadata.read();
    final path = metadata.lastBackupPath;
    if (path == null) {
      throw const BackupFormatException('本机没有可演练的最近备份。');
    }
    return _runRecoveryDrillForPath(
      path: path,
      password: password,
      resolveBaseFromCatalog: false,
    );
  }

  /// Read a catalog artifact for preview. Plaintext incremental artifacts
  /// are materialized with their recorded base; encrypted artifacts are
  /// returned locked so the UI can ask for a password.
  Future<BackupDocument> readCatalogBackup(BackupArtifact artifact) async {
    final source = await _files.readBackup(artifact.path);
    await _backfillArtifactBase(artifact, source);
    if (source.isEncrypted) return source;
    return _materializeCatalogIncremental(source);
  }

  /// Decrypt a catalog artifact and materialize its incremental base.
  Future<BackupDocument> unlockCatalogBackup(
    BackupArtifact artifact, {
    required String password,
  }) async {
    final source = await _files.readBackup(artifact.path);
    final unlocked = await _unwrapEncrypted(source, password: password);
    await _backfillArtifactBase(artifact, unlocked);
    return _materializeCatalogIncremental(unlocked);
  }

  /// Run a recovery drill for one catalog artifact.
  Future<BackupRecoveryDrillResult> runCatalogRecoveryDrill(
    BackupArtifact artifact, {
    String? password,
  }) {
    return _runRecoveryDrillForPath(
      path: artifact.path,
      password: password,
      resolveBaseFromCatalog: true,
    );
  }

  /// Delete one catalog artifact unless it is the current base/latest or
  /// another incremental artifact still depends on it.
  Future<int> deleteCatalogArtifact(BackupArtifact artifact) async {
    final metadata = await _metadata.read();
    if (artifact.path == metadata.lastBackupPath ||
        artifact.path == metadata.baseBackupPath) {
      throw const BackupArtifactProtectedException(
        '当前基础或最近备份不能单独删除。',
      );
    }
    final artifacts = await _catalog.read();
    var hasDependent = artifacts.any(
      (candidate) =>
          candidate.path != artifact.path &&
          candidate.baseBackupId == artifact.backupId,
    );
    if (!hasDependent) {
      for (final candidate in artifacts) {
        if (candidate.path == artifact.path ||
            candidate.kind != BackupArtifactKind.incremental ||
            candidate.baseBackupId != null) {
          continue;
        }
        try {
          final document = await _files.readBackup(candidate.path);
          await _backfillArtifactBase(candidate, document);
          if (document.baseBackupId == artifact.backupId) {
            hasDependent = true;
            break;
          }
        } catch (_) {
          // An unreadable candidate cannot safely prove independence.
          hasDependent = true;
          break;
        }
      }
    }
    if (hasDependent) {
      throw const BackupArtifactProtectedException(
        '仍有增量备份依赖该基础文件，不能删除。',
      );
    }
    final freedBytes = await _files.fileSize(artifact.path);
    await _files.deleteBackup(artifact.path);
    await _catalog.removeByPath(artifact.path);
    return freedBytes;
  }

  Future<BackupRecoveryDrillResult> _runRecoveryDrillForPath({
    required String path,
    required bool resolveBaseFromCatalog,
    String? password,
  }) async {
    final source = await _files.readBackup(path);
    final unlocked = source.isEncrypted
        ? await _unwrapEncrypted(source, password: password)
        : source;
    final resolved = resolveBaseFromCatalog
        ? await _materializeCatalogIncremental(unlocked)
        : await _materializeIncremental(unlocked);
    _validateRecoverableDocument(resolved);

    return BackupRecoveryDrillResult(
      path: path,
      backupId: unlocked.backupId,
      encrypted: source.isEncrypted,
      incremental: source.isIncremental,
      summary: resolved.summary,
      bundledAttachmentCount: resolved.attachmentBinaries.length,
      attachmentSizeBytes: resolved.attachmentSizeBytes,
    );
  }

  /// Pass-through helpers so the page does not need to depend on the
  /// port directly. Keeps the layering tight.
  Future<String?> shareFile(String source) => _files.shareBackup(source);

  /// Convenience for callers that already have the [BackupDocument] in
  /// memory (e.g. tests). Re-exports it through the configured port.
  Future<String> writeBackupToFile(
    BackupDocument document,
  ) async {
    final deviceId = await _deviceIdLoader();
    return _files.writeBackup(document, deviceId: deviceId);
  }

  Future<void> _recordCatalogArtifact({
    required BackupDocument document,
    required String path,
    required DateTime createdAt,
    required BackupArtifactSource source,
  }) async {
    final backupId = document.backupId;
    if (backupId == null) return;
    final kind = document.encrypted != null
        ? BackupArtifactKind.encrypted
        : document.isIncremental
            ? BackupArtifactKind.incremental
            : BackupArtifactKind.full;
    try {
      final sizeBytes = await _files.fileSize(path);
      final sha256Hex = await _files.fileSha256(path);
      await _catalog.upsert(
        BackupArtifact(
          backupId: backupId,
          path: path,
          createdAt: createdAt,
          kind: kind,
          source: source,
          sizeBytes: sizeBytes,
          sha256: sha256Hex,
          baseBackupId: document.baseBackupId,
        ),
      );
    } catch (_) {
      // Catalog metadata is auxiliary. Never turn a successful file
      // write into a failed backup because SharedPreferences failed.
    }
  }

  Future<void> _backfillArtifactBase(
    BackupArtifact artifact,
    BackupDocument document,
  ) async {
    if (artifact.baseBackupId != null || document.baseBackupId == null) return;
    try {
      await _catalog.upsert(
        artifact.copyWith(baseBackupId: document.baseBackupId),
      );
    } catch (_) {
      // Catalog metadata is auxiliary.
    }
  }

  // -- Helpers -----------------------------------------------------------

  List<Map<String, dynamic>> _asList(dynamic raw, String field) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw BackupFormatException('"$field" 字段不是数组');
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _restoreRecurring(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      await _recurring.deleteAll();
      return;
    }
    // Replace: clear then re-insert so removed rules don't linger.
    await _recurring.deleteAll();
    for (final raw in rows) {
      await _recurring.insertRaw(raw);
    }
  }

  Future<void> _restoreBudgets(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      await _budgets.deleteAll();
      return;
    }
    await _budgets.deleteAll();
    for (final raw in rows) {
      await _budgets.insertRaw(raw);
    }
  }

  Future<void> _restoreAttachments(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      await _attachments.deleteAll();
      return;
    }
    await _attachments.deleteAll();
    for (final raw in rows) {
      await _attachments.insertRaw(raw);
    }
  }

  Future<void> _restoreMerchantRules(
    List<Map<String, dynamic>> rows,
  ) async {
    final rules = <MerchantRule>[];
    for (final raw in rows) {
      final rule = _merchantRuleFromJson(raw);
      if (rule != null) rules.add(rule);
    }
    await _merchantRules.save(rules);
  }

  /// True when [bookId] only contains the accounts created by
  /// `LedgerRepository.seedIfEmpty()` or `createBook()`, and has no
  /// transactions, recurring rules, budgets, or attachments.
  Future<bool> _isReplaceablePlaceholderBook(String bookId) async {
    final counts = await _db.customSelect(
      '''
SELECT
  (SELECT COUNT(*) FROM transactions WHERE book_id = ?) AS transactions,
  (SELECT COUNT(*) FROM local_recurring_rules WHERE book_id = ?) AS recurring,
  (SELECT COUNT(*) FROM local_budgets WHERE book_id = ?) AS budgets,
  (SELECT COUNT(*) FROM local_attachments WHERE book_id = ?) AS attachments,
  (SELECT COUNT(*) FROM pending_mutations WHERE book_id = ?) AS pending,
  (SELECT COUNT(*) FROM sync_conflicts WHERE book_id = ?) AS conflicts
''',
      variables: [
        Variable<String>(bookId),
        Variable<String>(bookId),
        Variable<String>(bookId),
        Variable<String>(bookId),
        Variable<String>(bookId),
        Variable<String>(bookId),
      ],
      readsFrom: {},
    ).getSingle();
    if (counts.read<int>('transactions') > 0 ||
        counts.read<int>('recurring') > 0 ||
        counts.read<int>('budgets') > 0 ||
        counts.read<int>('attachments') > 0 ||
        counts.read<int>('pending') > 0 ||
        counts.read<int>('conflicts') > 0) {
      return false;
    }

    final accounts = await (_db.select(_db.accounts)
          ..where((account) => account.bookId.equals(bookId)))
        .get();
    if (accounts.isEmpty) return false;
    final expectedAccounts = <String, (String, String, String?)>{
      local_ids.accountKeyCash(bookId): ('Cash', 'asset', null),
      local_ids.accountKeyBank(bookId): ('Bank', 'asset', null),
      for (final category in defaultCategoryDefinitions)
        local_ids.accountId(bookId, category.key): (
          category.name,
          category.type,
          category.parentKey == null
              ? null
              : local_ids.accountId(bookId, category.parentKey!),
        ),
    };
    return accounts.every((account) {
      final expected = expectedAccounts[account.id];
      return expected != null &&
          account.name == expected.$1 &&
          account.type == expected.$2 &&
          account.parentAccountId == expected.$3;
    });
  }

  Future<BackupDocument?> _loadIncrementalBase() async {
    final metadata = await _metadata.read();
    final baseId = metadata.baseBackupId;
    final basePath = metadata.baseBackupPath;
    if (baseId == null || basePath == null) return null;
    try {
      final base = await _files.readBackup(basePath);
      if (base.isEncrypted || base.isIncremental || base.backupId != baseId) {
        return null;
      }
      return base;
    } catch (_) {
      return null;
    }
  }

  BackupDocument _buildIncremental({
    required BackupDocument current,
    required BackupDocument base,
  }) {
    final baseId = base.backupId;
    if (baseId == null) {
      throw const BackupFormatException('基础备份缺少 backupId');
    }
    if (!_sameBackupScope(current.bookIds, base.bookIds)) {
      throw const BackupFormatException('增量备份范围与基础备份不一致');
    }

    final changes = <String, dynamic>{};
    final deleted = <String, List<String>>{};
    final changedAttachmentIds = <String>{};
    for (final key in _deltaEntityKeys) {
      final currentRows = _asList(current.payload[key], key);
      final baseRows = _asList(base.payload[key], key);
      final currentById = _rowsById(currentRows, key);
      final baseById = _rowsById(baseRows, key);
      final changed = <Map<String, dynamic>>[];
      for (final entry in currentById.entries) {
        final previous = baseById[entry.key];
        if (previous == null ||
            jsonEncode(previous) != jsonEncode(entry.value)) {
          changed.add(entry.value);
          if (key == 'attachments') changedAttachmentIds.add(entry.key);
        }
      }
      changes[key] = changed;
      final removed = [
        for (final id in baseById.keys)
          if (!currentById.containsKey(id)) id,
      ];
      if (removed.isNotEmpty) deleted[key] = removed;
    }

    final baseBinaryHashes = <String, String>{
      for (final binary in base.attachmentBinaries)
        binary.id: sha256.convert(binary.bytes).toString(),
    };
    for (final binary in current.attachmentBinaries) {
      final digest = sha256.convert(binary.bytes).toString();
      if (baseBinaryHashes[binary.id] != digest) {
        changedAttachmentIds.add(binary.id);
      }
    }

    final changedIndex = [
      for (final entry in current.attachmentIndex)
        if (changedAttachmentIds.contains(entry['id'])) entry,
    ];
    final changedBinaries = [
      for (final binary in current.attachmentBinaries)
        if (changedAttachmentIds.contains(binary.id)) binary,
    ];

    return BackupDocument(
      summary: current.summary,
      payload: changes,
      bookIds: current.bookIds,
      attachmentIndex: changedIndex,
      attachmentBinaries: changedBinaries,
      schemaVersion: kIncrementalBackupSchemaVersion,
      backupId: current.backupId ?? const Uuid().v4(),
      baseBackupId: baseId,
      deleted: deleted,
    );
  }

  Future<BackupDocument> _materializeIncremental(
    BackupDocument document,
  ) async {
    if (!document.isIncremental) return document;
    final metadata = await _metadata.read();
    final baseId = metadata.baseBackupId;
    final basePath = metadata.baseBackupPath;
    if (baseId == null || basePath == null || baseId != document.baseBackupId) {
      throw const BackupFormatException(
        '该增量备份缺少本机基础文件，无法恢复；请使用完整备份。',
      );
    }

    final BackupDocument base;
    try {
      base = await _files.readBackup(basePath);
    } catch (error) {
      throw BackupFormatException(
        '增量备份的基础文件不可读：$error',
      );
    }
    if (base.isEncrypted || base.isIncremental || base.backupId != baseId) {
      throw const BackupFormatException(
        '增量备份的基础文件无效，无法恢复。',
      );
    }
    return _applyIncremental(base: base, delta: document);
  }

  Future<BackupDocument> _materializeCatalogIncremental(
    BackupDocument document,
  ) async {
    if (!document.isIncremental) return document;
    final baseId = document.baseBackupId;
    if (baseId == null) {
      throw const BackupFormatException('增量备份缺少 baseBackupId');
    }

    final metadata = await _metadata.read();
    final artifacts = await _catalog.read();
    final basePaths = <String>{
      if (metadata.baseBackupId == baseId && metadata.baseBackupPath != null)
        metadata.baseBackupPath!,
      for (final artifact in artifacts)
        if (artifact.backupId == baseId) artifact.path,
    };
    if (basePaths.isEmpty) {
      throw const BackupFormatException(
        '目录中没有该增量备份依赖的基础文件，无法恢复。',
      );
    }

    Object? lastError;
    for (final basePath in basePaths) {
      try {
        final base = await _files.readBackup(basePath);
        if (base.isEncrypted || base.isIncremental || base.backupId != baseId) {
          lastError = const BackupFormatException(
            '增量备份的基础文件无效。',
          );
          continue;
        }
        return _applyIncremental(base: base, delta: document);
      } catch (error) {
        lastError = error;
      }
    }
    throw BackupFormatException(
      '增量备份的基础文件不可读：$lastError',
    );
  }

  void _validateRecoverableDocument(BackupDocument document) {
    final summary = document.summary.toJson();
    for (final key in _deltaEntityKeys) {
      final rawRows = document.payload[key];
      final rows = _asList(rawRows, key);
      if (rawRows != null && rows.length != rawRows.length) {
        throw BackupFormatException('备份中的 $key 包含无效行');
      }
      _rowsById(rows, key);
      if (summary[key] != rows.length) {
        throw BackupFormatException(
          '备份 summary 与 $key 数量不一致：'
          '${summary[key]} != ${rows.length}',
        );
      }
    }

    final binaries = <String, AttachmentBinary>{};
    for (final binary in document.attachmentBinaries) {
      if (binaries.containsKey(binary.id)) {
        throw BackupFormatException('备份中存在重复附件二进制：${binary.id}');
      }
      binaries[binary.id] = binary;
    }

    final indexedIds = <String>{};
    for (final entry in document.attachmentIndex) {
      final id = entry['id'];
      if (id is! String || id.isEmpty) {
        throw const BackupFormatException('备份附件索引缺少 id');
      }
      if (!indexedIds.add(id)) {
        throw BackupFormatException('备份附件索引存在重复 id：$id');
      }
      final binary = binaries[id];
      if (binary == null) {
        throw BackupFormatException('备份附件索引缺少二进制：$id');
      }
      final size = entry['size'];
      if (size is! num || size.toInt() != binary.bytes.length) {
        throw BackupFormatException('备份附件大小不一致：$id');
      }
      final expectedSha = entry['sha256'];
      if (expectedSha is! String || expectedSha.isEmpty) {
        throw BackupFormatException('备份附件缺少 SHA-256：$id');
      }
      final actualSha = sha256.convert(binary.bytes).toString();
      if (actualSha != expectedSha) {
        throw BackupFormatException('备份附件 SHA-256 不一致：$id');
      }
    }
  }

  Future<BackupDocument> _encryptDocument(
    BackupDocument document, {
    required String password,
    required String deviceId,
  }) async {
    final envelopeBytes = await _files.buildPlaintextZip(
      document,
      deviceId: deviceId,
    );
    final encrypted = await _encryption.encrypt(
      envelopeBytes,
      password: password,
      publicMetadata: {
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'deviceId': deviceId,
        'summary': document.summary.toJson(),
        if (document.bookIds != null)
          'bookIds': document.bookIds!.toList()..sort(),
        if (document.attachmentIndex.isNotEmpty)
          'attachmentIndex': document.attachmentIndex,
      },
    );
    return document.withEncryption(encrypted);
  }

  BackupDocument _applyIncremental({
    required BackupDocument base,
    required BackupDocument delta,
  }) {
    final payload = <String, dynamic>{};
    for (final key in _deltaEntityKeys) {
      final merged = _rowsById(
        _asList(base.payload[key], key),
        key,
      );
      final deletedIds = delta.deleted[key] ?? const <String>[];
      for (final id in deletedIds) {
        merged.remove(id);
      }
      final changes = _asList(delta.payload[key], key);
      for (final row in changes) {
        merged[_rowId(row, key)] = row;
      }
      payload[key] = merged.values.toList();
    }

    final deletedAttachmentIds =
        (delta.deleted['attachments'] ?? const <String>[]).toSet();
    final attachmentIndex = <String, Map<String, dynamic>>{
      for (final row in base.attachmentIndex)
        if (row['id'] is String) row['id'] as String: row,
      for (final row in delta.attachmentIndex)
        if (row['id'] is String) row['id'] as String: row,
    }..removeWhere((id, _) => deletedAttachmentIds.contains(id));
    final binaries = <String, AttachmentBinary>{
      for (final binary in base.attachmentBinaries) binary.id: binary,
      for (final binary in delta.attachmentBinaries) binary.id: binary,
    }..removeWhere((id, _) => deletedAttachmentIds.contains(id));

    return BackupDocument(
      summary: delta.summary,
      payload: payload,
      bookIds: delta.bookIds ?? base.bookIds,
      attachmentIndex: attachmentIndex.values.toList(),
      attachmentBinaries: binaries.values.toList(),
      schemaVersion: kFullBackupSchemaVersion,
      backupId: delta.backupId,
    );
  }

  Map<String, Map<String, dynamic>> _rowsById(
    List<Map<String, dynamic>> rows,
    String key,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = _rowId(row, key);
      if (result.containsKey(id)) {
        throw BackupFormatException('备份中存在重复 $key：$id');
      }
      result[id] = row;
    }
    return result;
  }

  String _rowId(Map<String, dynamic> row, String key) {
    final id = row['id'];
    if (id is! String || id.isEmpty) {
      throw BackupFormatException('备份中的 $key 行缺少 id');
    }
    return id;
  }

  bool _sameBackupScope(Set<String>? a, Set<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null || a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// Decrypt an encrypted document using the user-supplied password
  /// and return a plain [BackupDocument] that [restore] can consume.
  /// Throws [BackupPasswordException] when the AES-GCM tag does not
  /// validate (covers wrong-password + tampered ciphertext).
  Future<BackupDocument> _unwrapEncrypted(
    BackupDocument document, {
    String? password,
  }) async {
    final encrypted = document.encrypted;
    if (encrypted == null) return document;
    if (password == null || password.isEmpty) {
      throw const BackupPasswordException(
        '该备份已加密，请提供密码以恢复',
      );
    }
    final plaintext = await _encryption.decrypt(
      encrypted,
      password: password,
    );
    return _files.parsePlaintextZip(plaintext);
  }

  DateTime? _parseNullableDate(String? raw) {
    if (raw == null) return null;
    return DateTime.parse(raw).toLocal();
  }

  // -- Row → JSON serializers -------------------------------------------

  Map<String, dynamic> _bookToJson(Book row) => {
        'id': row.id,
        'name': row.name,
        'currencyCode': row.currencyCode,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _accountToJson(Account row) => {
        'id': row.id,
        'bookId': row.bookId,
        'name': row.name,
        'type': row.type,
        'currencyCode': row.currencyCode,
        'parentAccountId': row.parentAccountId,
      };

  Map<String, dynamic> _transactionToJson(Transaction row) => {
        'id': row.id,
        'bookId': row.bookId,
        'occurredAt': row.occurredAt.toUtc().toIso8601String(),
        'description': row.description,
        'version': row.version,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
        'deletedAt': row.deletedAt?.toUtc().toIso8601String(),
        'source': row.source,
        'sourceEventFingerprint': row.sourceEventFingerprint,
      };

  Map<String, dynamic> _transactionEntryToJson(TransactionEntry row) => {
        'id': row.id,
        'transactionId': row.transactionId,
        'accountId': row.accountId,
        'amountMinor': row.amountMinor,
        'currencyCode': row.currencyCode,
        'entryIndex': row.entryIndex,
      };

  Map<String, dynamic> _recurringToJson(LocalRecurringRule row) => {
        'id': row.id,
        'bookId': row.bookId,
        'name': row.name,
        'kind': row.kind,
        'amountMinor': row.amountMinor.toString(),
        'categoryAccountId': row.categoryAccountId,
        'accountId': row.accountId,
        'dayOfMonth': row.dayOfMonth,
        'nextRunDate': row.nextRunDate,
        'active': row.active,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _budgetToJson(LocalBudgetRecord row) => {
        'id': row.id,
        'bookId': row.bookId,
        'name': row.name,
        'amountMinor': row.amountMinor.toString(),
        'categoryAccountId': row.categoryAccountId,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _attachmentToJson(LocalAttachmentRecord row) => {
        'id': row.id,
        'bookId': row.bookId,
        'transactionId': row.transactionId,
        'fileName': row.fileName,
        'mimeType': row.mime,
        'relativePath': row.relativePath,
        'createdAt': row.createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _merchantRuleToJson(MerchantRule rule) => {
        'id': rule.id,
        'categoryKey': rule.categoryKey,
        'needles': rule.needles,
      };

  MerchantRule? _merchantRuleFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final categoryKey = json['categoryKey'];
    final needles = json['needles'];
    if (id is! String ||
        categoryKey is! String ||
        needles is! List ||
        needles.isEmpty) {
      return null;
    }
    final clean = needles
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (clean.isEmpty) return null;
    return MerchantRule(id: id, categoryKey: categoryKey, needles: clean);
  }
}

/// Lightweight port for backup file I/O so tests can swap in an
/// in-memory implementation.
///
/// The port is responsible for picking the storage location (file path,
/// memory store, or any test fixture). The service hands it a fully-built
/// [BackupDocument] envelope; the port decides where it lives and how the
/// user gets the bytes back out.
abstract class BackupFilePort {
  /// Serialize [document] and persist it to a system-chosen location,
  /// returning an identifier the caller can share / display. The
  /// `deviceId` is embedded inside the envelope so future schema
  /// migrations know which client produced the file.
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  });

  /// Persist [document] to an automatic pre-restore safety-net path.
  /// The returned identifier is surfaced to the user so they can recover
  /// from a bad restore without us holding the file in memory.
  Future<String> writePreRestoreSafetyBackup(
    BackupDocument document, {
    required String deviceId,
  });

  /// Read the envelope from [source] (typically a user-chosen file path)
  /// and return the parsed [BackupDocument]. Pass [password] to unwrap
  /// a v3 encrypted container; omit it to receive the locked shell.
  Future<BackupDocument> readBackup(String source, {String? password});

  /// Open a file picker so the user can choose a `.ledgerly.json` /
  /// `.ledgerly.zip` / `.ledgerly.enc.zip` envelope. Returns `null`
  /// when the user cancels.
  Future<String?> pickBackupSource();

  /// Surface [source] to the user via the platform share sheet so they
  /// can save the bytes anywhere they like. Returns the chosen
  /// destination when the platform reports one (e.g. "Files saved"),
  /// otherwise `null`.
  Future<String?> shareBackup(String source);

  /// Return the persisted size, or `0` when [source] is missing.
  Future<int> fileSize(String source);

  /// Return the lowercase SHA-256 hex digest, or `null` when missing.
  Future<String?> fileSha256(String source);

  /// Delete [source]. Missing files are treated as already deleted.
  Future<void> deleteBackup(String source);

  /// Produce the v2-zip byte stream for [document] so the service can
  /// encrypt it before persisting.
  Future<Uint8List> buildPlaintextZip(
    BackupDocument document, {
    required String deviceId,
  });

  /// Reverse of [buildPlaintextZip]. Takes raw v2-zip bytes and
  /// returns a [BackupDocument] whose `encrypted` field is null.
  BackupDocument parsePlaintextZip(Uint8List bytes);
}
