import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/merchant_classifier.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('merge adds a new book and preserves existing local books', () async {
    final source = _Fixture('merge-source');
    final target = _Fixture('merge-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    final archived = await source.repository.createBook(name: 'Archive');
    await _addExpense(
      source,
      archived.id,
      description: 'archived expense',
    );
    final targetBook = (await target.repository.listBooks()).single;
    await _addExpense(
      target,
      targetBook.id,
      description: 'local expense',
    );

    final document = await source.service.export();
    final result = await target.service.merge(document);

    expect(result.addedBooks, 1);
    expect(result.replacedBooks, 0);
    expect(result.skippedBooks, 1);
    expect((await target.repository.listBooks()).length, 2);
    expect(await _transactionCount(target.db, targetBook.id), 1);
    expect(await _transactionCount(target.db, archived.id), 1);
  });

  test('merge replaces an untouched default placeholder book', () async {
    final source = _Fixture('placeholder-source');
    final target = _Fixture('placeholder-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    await _addExpense(
      source,
      defaultBookId,
      description: 'restored from backup',
    );
    final document = await source.service.export();
    final result = await target.service.merge(document);

    expect(result.addedBooks, 0);
    expect(result.replacedBooks, 1);
    expect(result.skippedBooks, 0);
    expect(await _transactionCount(target.db, defaultBookId), 1);
  });

  test('merge skips an existing book that already has local data', () async {
    final source = _Fixture('skip-source');
    final target = _Fixture('skip-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    await _addExpense(
      source,
      defaultBookId,
      description: 'backup expense',
    );
    await _addExpense(
      target,
      defaultBookId,
      description: 'local expense',
    );
    final document = await source.service.export();
    final result = await target.service.merge(document);

    expect(result.addedBooks, 0);
    expect(result.replacedBooks, 0);
    expect(result.skippedBooks, 1);
    expect(await _transactionCount(target.db, defaultBookId), 1);
    final descriptions = await target.db
        .customSelect(
          'SELECT description FROM transactions WHERE book_id = ?',
          variables: [Variable<String>(defaultBookId)],
          readsFrom: {},
        )
        .map((row) => row.read<String?>('description'))
        .get();
    expect(descriptions, ['local expense']);
  });

  test('merge does not treat a renamed default account as empty', () async {
    final source = _Fixture('renamed-account-source');
    final target = _Fixture('renamed-account-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    await _addExpense(
      source,
      defaultBookId,
      description: 'backup expense',
    );
    await (target.db.update(target.db.accounts)
          ..where(
              (account) => account.id.equals(accountKeyCash(defaultBookId))))
        .write(const AccountsCompanion(name: Value('Wallet')));

    final document = await source.service.export();
    final result = await target.service.merge(document);

    expect(result.skippedBooks, 1);
    expect(await _transactionCount(target.db, defaultBookId), 0);
    final name = await target.db
        .customSelect(
          'SELECT name FROM accounts WHERE id = ?',
          variables: [Variable<String>(accountKeyCash(defaultBookId))],
          readsFrom: {},
        )
        .map((row) => row.read<String>('name'))
        .getSingle();
    expect(name, 'Wallet');
  });

  test('merge does not write binaries for skipped books', () async {
    final source = _Fixture('attachment-source');
    final target = _Fixture('attachment-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    await _addExpense(
      target,
      defaultBookId,
      description: 'local data makes the book non-empty',
    );
    final attachmentId = const Uuid().v4();
    final relativePath = await source.attachments.writeBytes(
      id: attachmentId,
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    await source.attachments.insert(
      id: attachmentId,
      bookId: defaultBookId,
      transactionId: 'tx-stub',
      fileName: 'receipt.bin',
      mime: 'application/octet-stream',
      relativePath: relativePath,
    );

    final document = await source.service.export();
    final result = await target.service.merge(document);

    expect(result.skippedBooks, 1);
    expect(result.addedAttachments, 0);
    expect(target.byteStore.files, isEmpty);
  });

  test('merge rolls back all selected rows when one insert fails', () async {
    final source = _Fixture('rollback-source');
    final target = _Fixture('rollback-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    final atomicBook = await source.repository.createBook(name: 'Atomic');
    await _addExpense(
      source,
      atomicBook.id,
      description: 'atomic rollback',
    );
    final document = await source.service.export();
    final payload = Map<String, dynamic>.from(document.payload);
    final accounts =
        (payload['accounts'] as List).cast<Map<String, dynamic>>().toList();
    accounts.add(Map<String, dynamic>.from(accounts.first));
    payload['accounts'] = accounts;
    final malformed = BackupDocument(
      summary: document.summary,
      payload: payload,
      bookIds: document.bookIds,
    );

    await expectLater(
      target.service.merge(malformed),
      throwsA(anything),
    );

    expect(
      (await target.repository.listBooks()).map((book) => book.name),
      isNot(contains('Atomic')),
    );
    final accountCount = await target.db
        .customSelect(
          'SELECT COUNT(*) AS count FROM accounts WHERE book_id = ?',
          variables: [Variable<String>(atomicBook.id)],
          readsFrom: {},
        )
        .map((row) => row.read<int>('count'))
        .getSingle();
    expect(accountCount, 0);
  });

  test('merge unions merchant rules and keeps local rules on ID conflict',
      () async {
    final source = _Fixture('rule-source');
    final target = _Fixture('rule-target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.seed();
    await target.seed();

    await source.merchantRules.save([
      const MerchantRule(
        id: 'shared-rule',
        categoryKey: 'acc_food',
        needles: ['backup merchant'],
      ),
      const MerchantRule(
        id: 'backup-only',
        categoryKey: 'acc_transport',
        needles: ['backup taxi'],
      ),
    ]);
    final document = await source.service.export();

    await target.merchantRules.save([
      const MerchantRule(
        id: 'shared-rule',
        categoryKey: 'acc_shopping',
        needles: ['local merchant'],
      ),
    ]);
    final result = await target.service.merge(document);
    final rules = {
      for (final rule in await target.merchantRules.load()) rule.id: rule,
    };

    expect(result.addedMerchantRules, 1);
    expect(rules.keys, containsAll(['shared-rule', 'backup-only']));
    expect(rules['shared-rule']!.categoryKey, 'acc_shopping');
    expect(rules['shared-rule']!.needles, ['local merchant']);
  });
}

Future<void> _addExpense(
  _Fixture fixture,
  String bookId, {
  required String description,
}) {
  return LedgerAppService(
    fixture.repository,
    bookId: bookId,
  ).createExpense(
    expenseAccountId: accountKeyFood(bookId),
    fundingAccountId: accountKeyCash(bookId),
    amountMinor: BigInt.from(100),
    description: description,
  );
}

Future<int> _transactionCount(AppDatabase db, String bookId) async {
  final rows = await db.customSelect(
    'SELECT COUNT(*) AS count FROM transactions WHERE book_id = ?',
    variables: [Variable<String>(bookId)],
    readsFrom: {},
  ).getSingle();
  return rows.read<int>('count');
}

class _Fixture {
  _Fixture(String deviceId)
      : db = AppDatabase.forTesting(NativeDatabase.memory()),
        byteStore = MemoryAttachmentByteStore() {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => deviceId,
    );
    attachments = LocalAttachmentRepository(db, byteStore: byteStore);
    merchantRules = MerchantRuleStore();
    filePort = InMemoryBackupFilePort();
    service = BackupService(
      database: db,
      recurring: LocalRecurringRepository(db),
      budgets: LocalBudgetRepository(db),
      attachments: attachments,
      merchantRules: merchantRules,
      filePort: filePort,
      deviceIdLoader: () async => deviceId,
    );
  }

  final AppDatabase db;
  final MemoryAttachmentByteStore byteStore;
  late final InMemoryBackupFilePort filePort;
  late final LedgerRepository repository;
  late final LocalAttachmentRepository attachments;
  late final MerchantRuleStore merchantRules;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
