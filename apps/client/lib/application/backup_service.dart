import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/local_attachment_repository.dart';
import '../data/local_budget_repository.dart';
import '../data/local_recurring_repository.dart';
import 'backup_encryption.dart';
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
    this.schemaVersion = kBackupSchemaVersion,
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

  /// Total bytes the bundled attachments consume. Surfaced in the UI so
  /// the user can see how big the backup really is before sharing.
  int get attachmentSizeBytes =>
      attachmentBinaries.fold<int>(0, (sum, b) => sum + b.bytes.length);

  /// True when this document still needs a password before restore.
  bool get isEncrypted => encrypted != null;

  Map<String, dynamic> toEnvelope({required String deviceId}) {
    return {
      'kind': 'ledgerly-backup',
      'schemaVersion': kBackupSchemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      if (bookIds != null) 'bookIds': bookIds!.toList()..sort(),
      'summary': summary.toJson(),
      'data': payload,
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
    return BackupDocument(
      summary: BackupSummary.fromJson(
        Map<String, dynamic>.from(summaryJson),
      ),
      payload: Map<String, dynamic>.from(data),
      bookIds: bookIds,
      attachmentIndex: attachmentIndex,
      schemaVersion: version,
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

/// Thrown when a backup file is structurally invalid.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Current on-disk schema version. Bumped on any breaking change to the
/// `data` payload shape. Phase 9 bumped to `2` to add bundled
/// attachment binaries (zip container); legacy `1` files remain
/// readable so older backups keep restoring. Phase 10 keeps `2` for
/// the *plaintext* payload (no schema change) but adds a new outer
/// container at `schemaVersion: 3` for password-encrypted backups —
/// see [BackupDocument.encrypted] / [BackupEncryption].
const int kBackupSchemaVersion = 2;

/// Current outer-container schema version. Bumped when the on-disk
/// envelope changes shape: `3` introduced AES-256-GCM password
/// encryption (Phase 10). Plaintext v2 backups are still written by
/// this build; only the *encrypted* branch hits v3.
const int kEncryptedBackupSchemaVersion = 3;

/// Lowest schema version the current code can still restore. Older
/// files (v1) load but the restore preview warns the user that
/// attachment binaries were not bundled in that revision.
const int kMinReadableBackupSchemaVersion = 1;

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
  })  : _db = database,
        _recurring = recurring,
        _budgets = budgets,
        _attachments = attachments,
        _merchantRules = merchantRules,
        _files = filePort,
        _deviceIdLoader = deviceIdLoader,
        _metadata = metadata ?? BackupMetadataStore(),
        _encryption = encryption ?? BackupEncryption();

  final AppDatabase _db;
  final LocalRecurringRepository _recurring;
  final LocalBudgetRepository _budgets;
  final LocalAttachmentRepository _attachments;
  final MerchantRuleStore _merchantRules;
  final BackupFilePort _files;
  final Future<String> Function() _deviceIdLoader;
  final BackupMetadataStore _metadata;
  final BackupEncryption _encryption;

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
    );

    // Phase 10: if the caller supplied a password, seal the v2
    // payload into a password-encrypted envelope before returning.
    // The plaintext payload / binaries stay on the document so the
    // in-memory restore preview keeps working without retyping the
    // password.
    if (password != null && password.isNotEmpty) {
      final deviceId = await _deviceIdLoader();
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
      document = document.withEncryption(encrypted);
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
    final resolved = document.encrypted != null
        ? await _unwrapEncrypted(document, password: password)
        : document;
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
  }) async {
    final document = await export(bookIds: bookIds, password: password);
    final deviceId = await _deviceIdLoader();
    final path = await _files.writeBackup(document, deviceId: deviceId);
    await _metadata.record(
      path: path,
      at: DateTime.now().toUtc(),
      attachmentCount: document.attachmentBinaries.length,
      attachmentSizeBytes: document.attachmentSizeBytes,
      encrypted: document.encrypted != null,
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
    if (document.encrypted == null) return document;
    if (password == null || password.isEmpty) return document;
    return _unwrapEncrypted(document, password: password);
  }

  /// Decrypt a v3 document and return the inner v2 snapshot. Used by
  /// the restore UI after the user types the backup password.
  Future<BackupDocument> unlockEncrypted(
    BackupDocument document, {
    required String password,
  }) {
    return _unwrapEncrypted(document, password: password);
  }

  /// Snapshot the live database into a safety backup *before* running
  /// [restore]. Returns the safety destination so the UI can surface
  /// it to the user. The caller still owns calling [restore] with the
  /// user-chosen [document].
  Future<String> writeSafetyBackup() async {
    final current = await export();
    final deviceId = await _deviceIdLoader();
    return _files.writePreRestoreSafetyBackup(
      current,
      deviceId: deviceId,
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
