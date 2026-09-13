import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:ledgerly_client/application/backup_auto_password_store.dart';
import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_encryption.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_schedule.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/l10n/app_localizations.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';
import 'package:ledgerly_client/presentation/pages/data_governance_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';

typedef BooksLoader = FutureOr<List<Book>> Function();

void main() {
  late AppDatabase database;
  late LedgerRepository ledgerRepository;
  late LocalRecurringRepository recurring;
  late LocalBudgetRepository budgets;
  late LocalAttachmentRepository attachments;
  late MemoryAttachmentByteStore byteStore;
  late InMemoryBackupFilePort filePort;
  late BackupService backupService;
  late MerchantRuleStore merchantRules;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    ledgerRepository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'governance-test-device',
    );
    await ledgerRepository.seedIfEmpty();
    recurring = LocalRecurringRepository(database);
    budgets = LocalBudgetRepository(database);
    byteStore = MemoryAttachmentByteStore();
    attachments = LocalAttachmentRepository(
      database,
      byteStore: byteStore,
    );
    merchantRules = MerchantRuleStore();
    filePort = InMemoryBackupFilePort();
    backupService = BackupService(
      database: database,
      recurring: recurring,
      budgets: budgets,
      attachments: attachments,
      merchantRules: merchantRules,
      filePort: filePort,
      deviceIdLoader: () async => 'governance-test-device',
      encryption: BackupEncryption.testing(),
    );
  });

  /// Most tests render with a single seeded book (the default). The
  /// Phase 8 selective-backup tests need multiple books to exercise
  /// the chip selector.
  Future<List<Book>> loadBooks() => ledgerRepository.listBooks();

  tearDown(() => database.close());

  testWidgets('renders the three sections with the right CTAs', (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(find.text(l10n.dataGovernanceTitle), findsWidgets);
    expect(find.text(l10n.dataGovernanceSectionBackup), findsOneWidget);
    expect(find.text(l10n.dataGovernanceSectionDanger), findsOneWidget);
    expect(
      find.byKey(const Key('data-governance-export-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-governance-restore-pick')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-governance-wipe-action')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('data-governance-wipe')), findsOneWidget);
    expect(find.byKey(const Key('data-governance-export')), findsOneWidget);
    expect(find.byKey(const Key('data-governance-restore')), findsOneWidget);
  });

  testWidgets('export writes the snapshot through the file port',
      (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.tap(
      find.byKey(const Key('data-governance-export-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(filePort.envelopes, isNotEmpty);
    final path = filePort.envelopes.keys.first;
    expect(
      find.byKey(const Key('data-governance-export-path')),
      findsOneWidget,
    );
    expect(find.text(path), findsOneWidget);
  });

  testWidgets('restore preview lists counts and confirms through safety net',
      (tester) async {
    final document = await backupService.export();
    filePort.pickResult = 'picked-backup';
    filePort.envelopes['picked-backup'] = document;

    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.tap(
      find.byKey(const Key('data-governance-restore-pick')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const Key('data-governance-restore-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-governance-restore-summary')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-restore-confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-restore-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('data-governance-restore-dialog-confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final safetyEntries = filePort.envelopes.entries
        .where((entry) => entry.key.startsWith('memory-safety'))
        .toList();
    expect(safetyEntries.length, 1);
  });

  testWidgets('restore preview can switch to merge mode and reports its result',
      (tester) async {
    final document = await backupService.export();
    filePort.pickResult = 'picked-merge-backup';
    filePort.envelopes['picked-merge-backup'] = document;

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-restore-pick')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text(l10n.dataGovernanceRestoreModeMerge));
    await tester.pump();
    expect(
      find.byKey(const Key('data-governance-restore-merge-hint')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-restore-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.dataGovernanceRestoreConfirmMergeTitle),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-restore-dialog-confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(l10n.dataGovernanceRestoreMergeSuccess(0, 1, 0)),
      findsOneWidget,
    );
  });

  testWidgets('wipe requires the user to type DELETE', (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.tap(
      find.byKey(const Key('data-governance-wipe-action')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-wipe-dialog')),
      findsOneWidget,
    );

    // Confirm button stays disabled while the input is empty.
    final confirm = find.byKey(const Key('data-governance-wipe-confirm'));
    expect(confirm, findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('data-governance-wipe-input')),
      'delete',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('data-governance-wipe-input')),
      'DELETE',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final books = await ledgerRepository.listBooks();
    // The seeded book gets removed when wipeLocalData completes.
    expect(books, isEmpty);
  });

  testWidgets('cancel restores the empty state without wiping', (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final booksBefore = await ledgerRepository.listBooks();

    await tester.tap(
      find.byKey(const Key('data-governance-wipe-action')),
    );
    await tester.pumpAndSettle();
    // Cancel the dialog without typing anything.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final booksAfter = await ledgerRepository.listBooks();
    expect(booksAfter.length, booksBefore.length);
  });

  testWidgets('fresh install shows "never backed up" without banner',
      (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-status-card')),
      findsOneWidget,
    );
    expect(find.text(l10n.dataGovernanceStatusTitle), findsOneWidget);
    expect(find.text(l10n.dataGovernanceStatusNever), findsOneWidget);
    expect(
      find.byKey(const Key('data-governance-stale-banner')),
      findsNothing,
    );
  });

  testWidgets('export refreshes the status card and stops advertising stale',
      (tester) async {
    // Pretend the last backup happened 30 days ago so the banner is
    // visible when the page first opens. Exporting should clear it.
    final staleAt = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackupMetadataStore.kLastBackupAt,
      staleAt.toIso8601String(),
    );
    await prefs.setString(
      BackupMetadataStore.kLastBackupPath,
      '/fake/stale/backup.json',
    );

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-stale-banner')),
      findsOneWidget,
    );
    expect(find.text(l10n.dataGovernanceStaleBannerTitle(30)), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('data-governance-stale-banner-action')),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(filePort.envelopes, isNotEmpty);
    expect(
      find.byKey(const Key('data-governance-stale-banner')),
      findsNothing,
    );
    expect(find.text(l10n.dataGovernanceStatusNever), findsNothing);
  });

  testWidgets('stale banner appears when last backup is older than 14 days',
      (tester) async {
    final staleAt = DateTime.now().toUtc().subtract(const Duration(days: 21));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackupMetadataStore.kLastBackupAt,
      staleAt.toIso8601String(),
    );

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-stale-banner')),
      findsOneWidget,
    );
    expect(find.text(l10n.dataGovernanceStaleBannerTitle(21)), findsOneWidget);
  });

  testWidgets('wipeLocalData clears the persisted backup metadata',
      (tester) async {
    // Seed a recent backup timestamp through SharedPreferences and
    // call the service directly. This exercises the real wipe path
    // without depending on the UI's dialog plumbing.
    final recentAt = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackupMetadataStore.kLastBackupAt,
      recentAt.toIso8601String(),
    );
    await prefs.setString(
      BackupMetadataStore.kLastBackupPath,
      '/fake/recent/backup.json',
    );

    await backupService.wipeLocalData();

    final prefsAfter = await SharedPreferences.getInstance();
    expect(prefsAfter.getString(BackupMetadataStore.kLastBackupAt), isNull);
    expect(prefsAfter.getString(BackupMetadataStore.kLastBackupPath), isNull);
  });

  testWidgets('data governance page reacts to invalidated metadata after wipe',
      (tester) async {
    // First call wipe directly so the persisted record is empty. The
    // UI test for the dialog-driven wipe path is covered separately
    // because the dialog dismissal triggers a chain of async work
    // (transaction �?SharedPreferences writes �?FutureProvider re-read)
    // that does not all flush inside `pumpAndSettle`.
    await backupService.wipeLocalData();

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(find.text(l10n.dataGovernanceStatusNever), findsOneWidget);
    expect(
      find.byKey(const Key('data-governance-stale-banner')),
      findsNothing,
    );
  });

  testWidgets(
      'export button reflects the current book selection (single-book case)',
      (tester) async {
    // With only the seeded default book there is nothing to choose
    // from, so the chip selector is hidden and the export button
    // shows the count of *every* book in plain language.
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    final exportButton = find.byKey(const Key('data-governance-export-action'));

    expect(
      find.byKey(const Key('data-governance-book-selector')),
      findsNothing,
    );
    expect(
      exportButton,
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: exportButton,
        matching: find.text(l10n.dataGovernanceExportAll(1)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('export button scopes the snapshot to the chosen book subset',
      (tester) async {
    // Seed a second book so the chip selector appears. `createBook`
    // issues a real database transaction whose IO does not advance
    // under the fake test clock, so we drop into `runAsync` for the
    // setup work before pumping the widget tree.
    late final List<Book> books;
    await tester.runAsync(() async {
      await ledgerRepository.createBook(name: 'Family');
      books = await loadBooks();
    });
    expect(books.length, 2);

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    final exportButton = find.byKey(const Key('data-governance-export-action'));

    expect(
      find.byKey(const Key('data-governance-book-selector')),
      findsOneWidget,
    );
    expect(
      exportButton,
      findsOneWidget,
    );
    // Default state: nothing chosen, button advertises the full set.
    expect(
      find.descendant(
        of: exportButton,
        matching: find.text(l10n.dataGovernanceExportAll(2)),
      ),
      findsOneWidget,
    );

    // Initial state with the chip selector visible: nothing is
    // pre-selected, so the export button advertises the full set
    // and tapping the export button without toggling a chip would
    // bundle every book. Pick just that one book to scope the
    // resulting snapshot.
    await tester.tap(
      find.byKey(Key('data-governance-book-chip-${books[1].id}')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: exportButton,
        matching: find.text(l10n.dataGovernanceExportSelected(1)),
      ),
      findsOneWidget,
    );

    // Press export and check the envelope only contains the chosen book.
    debugPrint('[p8] tapping export button');
    await tester.tap(exportButton);
    debugPrint('[p8] tapped, running export');
    // Phase 9 added sha256 + zip packaging to exportToFile; let the
    // real async chain run to completion outside of the fake clock
    // so the future actually resolves before we assert against it.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    debugPrint('[p8] pumping');
    await tester.pump();
    debugPrint('[p8] drained snackbar');
    // Drain the success snackbar's auto-dismiss timer so the framework
    // does not flag a "Timer still pending" assertion at teardown.
    await tester.pump(const Duration(seconds: 5));

    final documents = filePort.envelopes.values.toList();
    expect(documents, isNotEmpty);
    final document = documents.last;
    expect(document.bookIds, isNotNull);
    expect(document.bookIds!.length, 1);
    expect(document.bookIds!.first, books[1].id);
    final booksInPayload =
        (document.payload['books'] as List).cast<Map<String, dynamic>>();
    expect(booksInPayload.length, 1);
    expect(booksInPayload.first['id'], books[1].id);
  });

  // -----------------------------------------------------------------
  // Phase 9: attachment binary bundling
  // -----------------------------------------------------------------

  testWidgets('status card surfaces the bundled attachment count + size',
      (tester) async {
    // Seed the metadata store as if a previous backup had bundled
    // three attachments totalling 12.3 MB.
    final prefs = await SharedPreferences.getInstance();
    final recentAt = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    await prefs.setString(
      BackupMetadataStore.kLastBackupAt,
      recentAt.toIso8601String(),
    );
    await prefs.setString(
      BackupMetadataStore.kLastBackupPath,
      '/fake/with-attachments.zip',
    );
    await prefs.setInt(BackupMetadataStore.kLastAttachmentCount, 3);
    await prefs.setInt(
      BackupMetadataStore.kLastAttachmentSize,
      12 * 1024 * 1024 + 300 * 1024,
    );

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-status-attachments')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataGovernanceStatusAttachments(3, '12.3 MB')),
      findsOneWidget,
    );
  });

  testWidgets(
      'export bundles attachment binaries inside the zip and restores them',
      (tester) async {
    final books = await ledgerRepository.listBooks();
    final bookId = books.first.id;

    // Drop an attachment's metadata + binary onto the device so the
    // export has something to bundle. We mirror the production
    // upload flow: write the bytes first to learn the relative path,
    // then insert the metadata row pointing at that path.
    /// Drop an attachment's metadata + binary onto the device so the
    // export has something to bundle. We mirror the production
    // upload flow: write the bytes first to learn the relative path,
    // then insert the metadata row pointing at that path. The id
    // is generated up-front so the byte store key and the metadata
    // id line up exactly.
    final id = const Uuid().v4();
    final payload =
        Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
    final relativePath = await attachments.writeBytes(id: id, bytes: payload);
    final meta = await attachments.insert(
      id: id,
      bookId: bookId,
      transactionId: 'tx-stub',
      fileName: 'receipt.jpg',
      mime: 'image/jpeg',
      relativePath: relativePath,
    );

    // Run an export through the service directly so we can inspect
    // both the in-memory document and the bytes the port wrote.
    final path = await backupService.exportToFile();
    expect(filePort.rawFiles[path], isNotNull);

    final document = filePort.envelopes[path]!;
    expect(document.attachmentBinaries, hasLength(1));
    expect(document.attachmentBinaries.first.id, meta.id);
    expect(document.attachmentBinaries.first.bytes, equals(payload));
    expect(document.attachmentIndex, hasLength(1));
    final indexEntry = document.attachmentIndex.first;
    expect(indexEntry['id'], meta.id);
    expect(indexEntry['size'], payload.length);
    expect(indexEntry['relativePath'], meta.relativePath);

    // Metadata store should reflect the bundled attachment stats
    // before wipe resets them — read straight after export so we
    // see the production flow.
    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastAttachmentCount, 1);
    expect(metadata.lastAttachmentSizeBytes, payload.length);

    // Wipe so restore starts from a clean slate, then restore from the
    // same document and confirm the binary bytes round-trip exactly.
    await backupService.wipeLocalData();
    expect(byteStore.files[meta.relativePath], isNull);

    await backupService.restore(document);
    final restored = await attachments.readBytes(meta.relativePath);
    expect(restored, isNotNull);
    expect(restored, equals(payload));
  });

  testWidgets('legacy v1 envelopes remain readable without binaries',
      (tester) async {
    // Build a fake Phase-6 envelope (schemaVersion=1, no
    // attachmentIndex) and feed it through the in-memory port.
    final legacyEnvelope = {
      'kind': 'ledgerly-backup',
      'schemaVersion': 1,
      'exportedAt': '2026-09-13T10:00:00.000Z',
      'deviceId': 'legacy',
      'summary': {
        'books': 0,
        'accounts': 0,
        'transactions': 0,
        'transactionEntries': 0,
        'recurringRules': 0,
        'budgets': 0,
        'attachments': 0,
        'merchantRules': 0,
      },
      'data': {
        'books': <Map<String, dynamic>>[],
        'accounts': <Map<String, dynamic>>[],
        'transactions': <Map<String, dynamic>>[],
        'transactionEntries': <Map<String, dynamic>>[],
        'recurringRules': <Map<String, dynamic>>[],
        'budgets': <Map<String, dynamic>>[],
        'attachments': <Map<String, dynamic>>[],
        'merchantRules': <Map<String, dynamic>>[],
      },
    };

    final doc = BackupDocument.fromEnvelope(
      Map<String, dynamic>.from(legacyEnvelope),
    );
    expect(doc.attachmentIndex, isEmpty);
    expect(doc.attachmentBinaries, isEmpty);
    expect(doc.summary.total, 0);
  });

  // -----------------------------------------------------------------
  // Phase 10: password-encrypted backup
  // -----------------------------------------------------------------

  testWidgets('encrypted export writes a password-protected envelope',
      (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-encrypt-checkbox')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('data-governance-encrypt-password')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataGovernanceExportEncryptedAll(1)),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('data-governance-encrypt-password')),
      'password123',
    );
    await tester.enterText(
      find.byKey(const Key('data-governance-encrypt-password-confirm')),
      'password123',
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('data-governance-export-action')),
    );
    await tester.tap(
      find.byKey(const Key('data-governance-export-action')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(filePort.envelopes, isNotEmpty);
    final document = filePort.envelopes.values.last;
    expect(document.encrypted, isNotNull);
    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastBackupEncrypted, isTrue);
  });

  testWidgets('wrong restore password stays on the unlock dialog',
      (tester) async {
    late final String path;
    await tester.runAsync(() async {
      path = await backupService.exportToFile(password: 'password123');
    });
    filePort.pickResult = path;

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-restore-pick')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const Key('data-governance-unlock-dialog')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('data-governance-unlock-password')),
      'wrong-password',
    );
    await tester.tap(
      find.byKey(const Key('data-governance-unlock-submit')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();

    expect(find.text(l10n.dataGovernanceUnlockWrongPassword), findsOneWidget);
    expect(
      find.byKey(const Key('data-governance-unlock-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data-governance-restore-preview')),
      findsNothing,
    );
  });

  testWidgets('correct restore password unlocks the preview', (tester) async {
    late final String path;
    await tester.runAsync(() async {
      path = await backupService.exportToFile(password: 'password123');
    });
    filePort.pickResult = path;

    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.tap(
      find.byKey(const Key('data-governance-restore-pick')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(
      find.byKey(const Key('data-governance-unlock-password')),
      'password123',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('data-governance-unlock-submit')),
    );
    await tester.pump();
    await _flushBackupCrypto(tester);
    await tester.pumpAndSettle();

    if (find
        .byKey(const Key('data-governance-unlock-dialog'))
        .evaluate()
        .isNotEmpty) {
      final field = tester.widget<TextField>(
        find.byKey(const Key('data-governance-unlock-password')),
      );
      fail('unlock dialog still open: ${field.decoration?.errorText}');
    }
    expect(
      find.byKey(const Key('data-governance-restore-preview')),
      findsOneWidget,
    );
  });

  testWidgets('three wrong passwords lock the unlock dialog', (tester) async {
    late final String path;
    await tester.runAsync(() async {
      path = await backupService.exportToFile(password: 'password123');
    });
    filePort.pickResult = path;

    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.tap(
      find.byKey(const Key('data-governance-restore-pick')),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final submit = find.byKey(const Key('data-governance-unlock-submit'));
    for (var i = 0; i < kBackupUnlockMaxAttempts; i++) {
      await tester.enterText(
        find.byKey(const Key('data-governance-unlock-password')),
        'wrong-password',
      );
      await tester.tap(submit);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
    }

    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('plaintext restore preview warns that the file is unencrypted',
      (tester) async {
    final document = await backupService.export();
    filePort.pickResult = 'picked-backup';
    filePort.envelopes['picked-backup'] = document;

    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.tap(
      find.byKey(const Key('data-governance-restore-pick')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const Key('data-governance-restore-unencrypted-warning')),
      findsOneWidget,
    );
  });

  testWidgets('status card advertises that the last backup was encrypted',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final recentAt = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    await prefs.setString(
      BackupMetadataStore.kLastBackupAt,
      recentAt.toIso8601String(),
    );
    await prefs.setBool(BackupMetadataStore.kLastBackupEncrypted, true);

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-status-encrypted')),
      findsOneWidget,
    );
    expect(find.text(l10n.dataGovernanceStatusEncrypted), findsOneWidget);
  });

  testWidgets('incremental option disables when encrypted export is selected',
      (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    final incremental = find.byKey(
      const Key('data-governance-incremental-checkbox'),
    );

    expect(
      tester.widget<CheckboxListTile>(incremental).onChanged,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-encrypt-checkbox')),
    );
    await tester.pump();

    final disabled = tester.widget<CheckboxListTile>(incremental);
    expect(disabled.value, isFalse);
    expect(disabled.onChanged, isNull);
    expect(
      find.text(l10n.dataGovernanceIncrementalEncryptedDisabled),
      findsOneWidget,
    );
  });

  testWidgets('status card marks an incremental backup as local-only',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackupMetadataStore.kLastBackupAt,
      DateTime.now().toUtc().toIso8601String(),
    );
    await prefs.setBool(BackupMetadataStore.kLastBackupIncremental, true);

    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-status-incremental')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataGovernanceStatusIncremental),
      findsOneWidget,
    );
  });

  testWidgets('backup catalog shows count and confirms cleanup',
      (tester) async {
    await backupService.exportToFile();
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(
      find.byKey(const Key('data-governance-backup-catalog')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataGovernanceLocalBackups(1, '0.0 MB')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-cleanup-action')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-governance-cleanup-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-cleanup-confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(l10n.dataGovernanceCleanupNoChanges),
      findsOneWidget,
    );
  });

  testWidgets('catalog artifact can run a recovery drill', (tester) async {
    await backupService.exportToFile();
    final artifact = (await BackupCatalogStore().read()).single;
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await _expandBackupCatalog(tester);
    expect(
      find.byKey(Key('data-governance-artifact-${artifact.backupId}')),
      findsOneWidget,
    );
    await _selectArtifactAction(tester, artifact, 'drill');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-drill-result-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('catalog artifact can load into the restore preview',
      (tester) async {
    await backupService.exportToFile();
    final artifact = (await BackupCatalogStore().read()).single;
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await _expandBackupCatalog(tester);
    await _selectArtifactAction(tester, artifact, 'restore');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-restore-preview')),
      findsOneWidget,
    );
  });

  testWidgets('catalog artifact delete confirms and removes the file',
      (tester) async {
    await backupService.exportToFile();
    final safetyPath = await backupService.writeSafetyBackup();
    final safety = (await BackupCatalogStore().read()).firstWhere(
      (artifact) => artifact.path == safetyPath,
    );
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await _expandBackupCatalog(tester);
    await _selectArtifactAction(tester, safety, 'delete');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-governance-artifact-delete-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('data-governance-artifact-delete-confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(filePort.rawFiles.containsKey(safetyPath), isFalse);
    expect(
      (await BackupCatalogStore().read()).map((artifact) => artifact.path),
      isNot(contains(safetyPath)),
    );
  });

  testWidgets('catalog encrypted artifact can rotate its password',
      (tester) async {
    final oldPath = await backupService.exportToFile(
      password: 'password123',
    );
    final artifact = (await BackupCatalogStore().read()).single;
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await _expandBackupCatalog(tester);
    await _selectArtifactAction(tester, artifact, 'rotate');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-governance-artifact-rotate-dialog')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('data-governance-artifact-rotate-old')),
      'password123',
    );
    await tester.enterText(
      find.byKey(const Key('data-governance-artifact-rotate-new')),
      'newpassword456',
    );
    await tester.enterText(
      find.byKey(const Key('data-governance-artifact-rotate-confirm')),
      'newpassword456',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('data-governance-artifact-rotate-submit')),
    );
    await tester.pump();
    await _flushBackupCrypto(tester);
    await tester.pumpAndSettle();

    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastBackupPath, isNot(oldPath));
    expect(metadata.lastBackupId, isNotNull);
    expect(filePort.rawFiles.containsKey(oldPath), isTrue);
    expect(filePort.rawFiles, hasLength(2));
  });

  testWidgets('incremental backup can be consolidated for sharing',
      (tester) async {
    await backupService.exportToFile();
    await backupService.exportToFile(incremental: true);
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    final consolidate = find.byKey(
      const Key('data-governance-consolidate-action'),
    );
    expect(consolidate, findsOneWidget);

    await tester.tap(consolidate);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-governance-portable-password-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('data-governance-portable-password-submit')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(consolidate, findsNothing);
    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastBackupEncrypted, isFalse);
    final share = tester.widget<OutlinedButton>(
      find.byKey(const Key('data-governance-export-share')),
    );
    expect(share.onPressed, isNotNull);
  });

  testWidgets('portable backup can be encrypted with a password',
      (tester) async {
    final basePath = await backupService.exportToFile();
    final base = filePort.envelopes[basePath]!;
    await backupService.exportToFile(incremental: true);
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-consolidate-action')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('data-governance-portable-password')),
      'short',
    );
    await tester.pump();
    expect(
      find.text(l10n.dataGovernancePasswordTooShort),
      findsOneWidget,
    );
    final disabledSubmit = tester.widget<FilledButton>(
      find.byKey(const Key('data-governance-portable-password-submit')),
    );
    expect(disabledSubmit.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('data-governance-portable-password')),
      'password123',
    );
    await tester.enterText(
      find.byKey(const Key('data-governance-portable-password-confirm')),
      'password123',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('data-governance-portable-password-submit')),
    );
    await tester.pump();
    await _flushBackupCrypto(tester);
    await tester.pumpAndSettle();

    final metadata = await BackupMetadataStore().read();
    expect(metadata.lastBackupEncrypted, isTrue);
    expect(metadata.lastBackupIncremental, isFalse);
    expect(metadata.baseBackupId, base.backupId);
    expect(metadata.baseBackupPath, basePath);
    final portable = filePort.envelopes[metadata.lastBackupPath!]!;
    expect(portable.isEncrypted, isTrue);
    expect(portable.isIncremental, isFalse);
  });

  testWidgets('integrity check reports corrupted catalog files',
      (tester) async {
    final path = await backupService.exportToFile();
    filePort.rawFiles[path] = Uint8List.fromList([1, 2, 3]);
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-verify-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-integrity-dialog')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataGovernanceVerifyIssuesTitle),
      findsOneWidget,
    );
  });

  testWidgets('recovery drill validates the latest plaintext backup',
      (tester) async {
    await backupService.exportToFile();
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-drill-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-drill-result-dialog')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.dataGovernanceRecoveryDrillSuccessTitle),
      findsOneWidget,
    );
  });

  testWidgets('encrypted recovery drill requires the correct password',
      (tester) async {
    await backupService.exportToFile(password: 'password123');
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.tap(
      find.byKey(const Key('data-governance-drill-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const Key('data-governance-drill-password-dialog')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('data-governance-drill-password')),
      'wrong-password',
    );
    await tester.tap(
      find.byKey(const Key('data-governance-drill-submit')),
    );
    await tester.pump();
    await _flushBackupCrypto(tester);
    expect(
      find.text(l10n.dataGovernanceUnlockWrongPassword),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('data-governance-drill-password')),
      'password123',
    );
    await tester.tap(
      find.byKey(const Key('data-governance-drill-submit')),
    );
    await tester.pump();
    await _flushBackupCrypto(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('data-governance-drill-result-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('auto-backup switch is off by default', (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(find.text(l10n.dataGovernanceAutoBackup), findsOneWidget);
    expect(
      find.byKey(const Key('data-governance-auto-backup-warning')),
      findsOneWidget,
    );
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('data-governance-auto-backup-switch')),
    );
    expect(toggle.value, isFalse);
    final encryptedToggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('data-governance-auto-encrypt-switch')),
    );
    expect(encryptedToggle.value, isFalse);
  });

  testWidgets('encrypted auto backup stores and clears its password',
      (tester) async {
    final passwordStore = MemoryBackupAutoPasswordStore();
    await _pumpPage(
      tester,
      backupService,
      booksLoader: loadBooks,
      autoPasswordStore: passwordStore,
    );
    final switchFinder = find.byKey(
      const Key('data-governance-auto-encrypt-switch'),
    );

    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-governance-auto-encrypt-password-dialog')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('data-governance-auto-encrypt-password')),
      'password123',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(
        const Key('data-governance-auto-encrypt-password-confirm'),
      ),
      'password123',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const Key('data-governance-auto-encrypt-password-submit'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('data-governance-auto-encrypt-password-dialog')),
      findsNothing,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BackupScheduleStore.kEncrypted), isTrue);
    expect(passwordStore.password, 'password123');

    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(prefs.getBool(BackupScheduleStore.kEncrypted), isFalse);
    expect(passwordStore.password, isNull);
  });

  testWidgets('enabling auto backup persists and writes a baseline snapshot',
      (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.ensureVisible(
      find.byKey(const Key('data-governance-auto-backup-switch')),
    );
    await tester.tap(
      find.byKey(const Key('data-governance-auto-backup-switch')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BackupScheduleStore.kEnabled), isTrue);
    expect(
      prefs.getInt(BackupScheduleStore.kIntervalDays),
      kBackupAutoDefaultIntervalDays,
    );
    expect(filePort.envelopes, isNotEmpty);
    expect(filePort.envelopes.values.single.encrypted, isNull);

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('data-governance-auto-backup-switch')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('interval chip persists the chosen cadence', (tester) async {
    await _pumpPage(tester, backupService, booksLoader: loadBooks);

    await tester.ensureVisible(
      find.byKey(const Key('data-governance-auto-interval-14')),
    );
    await tester.tap(
      find.byKey(const Key('data-governance-auto-interval-14')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(BackupScheduleStore.kIntervalDays), 14);
    expect(prefs.getBool(BackupScheduleStore.kEnabled), isNot(true));
    expect(filePort.envelopes, isEmpty);

    final chip = tester.widget<FilterChip>(
      find.byKey(const Key('data-governance-auto-interval-14')),
    );
    expect(chip.selected, isTrue);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  BackupService service, {
  BooksLoader? booksLoader,
  BackupAutoPasswordStore? autoPasswordStore,
}) async {
  // The page renders both the backup section and a danger section.
  // The wipe button lives at the bottom of the layout, so we use a
  // taller test viewport than the default 800x600.
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backupServiceProvider.overrideWithValue(service),
        booksProvider.overrideWith(
          (ref) => booksLoader?.call() ?? Future.value(const <Book>[]),
        ),
        if (autoPasswordStore != null)
          backupAutoPasswordStoreProvider.overrideWithValue(autoPasswordStore),
      ],
      child: const MaterialApp(
        home: DataGovernancePage(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _expandBackupCatalog(WidgetTester tester) async {
  final catalog = find.byKey(const Key('data-governance-artifact-list'));
  await tester.ensureVisible(catalog);
  await tester.tap(catalog);
  await tester.pumpAndSettle();
}

Future<void> _selectArtifactAction(
  WidgetTester tester,
  BackupArtifact artifact,
  String action,
) async {
  final actions = find.byKey(
    Key('data-governance-artifact-${artifact.backupId}-actions'),
  );
  await tester.ensureVisible(actions);
  await tester.tap(actions);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      Key('data-governance-artifact-${artifact.backupId}-$action'),
    ),
  );
  await tester.pump();
}

Future<void> _flushBackupCrypto(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }
}
