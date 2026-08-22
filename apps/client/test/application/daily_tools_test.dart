import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:ledgerly_client/application/csv_bill_parser.dart';
import 'package:ledgerly_client/application/csv_text.dart';
import 'package:ledgerly_client/application/feed_search.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/ledger_csv.dart';
import 'package:ledgerly_client/application/recurring_date.dart';
import 'package:ledgerly_client/application/recurring_scheduler.dart';
import 'package:ledgerly_client/auth/app_lock_store.dart';
import 'package:ledgerly_client/auth/biometric_auth.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/l10n/l10n.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));

  test('feed search matches note, category, account, and amount', () {
    final lunch = TransactionSummary(
      id: '1',
      occurredAt: DateTime.utc(2026, 8, 4),
      description: '星巴克拿铁',
      entryCount: 2,
      kind: TransactionSummaryKind.expense,
      amountMinor: BigInt.from(3200),
      categoryName: 'Food',
      accountName: 'Cash',
    );

    expect(matchesFeedQuery(lunch, '拿铁', l10n), isTrue);
    expect(matchesFeedQuery(lunch, '餐饮', l10n), isTrue);
    expect(matchesFeedQuery(lunch, '现金', l10n), isTrue);
    expect(matchesFeedQuery(lunch, '32.00', l10n), isTrue);
    expect(matchesFeedQuery(lunch, '工资', l10n), isFalse);
    expect(filterFeedTransactions([lunch], '', l10n), [lunch]);
  });

  test('ledger csv includes BOM and localized columns', () {
    final csv = buildLedgerCsv(
      [
        TransactionSummary(
          id: '1',
          occurredAt: DateTime.utc(2026, 8, 4, 4),
          description: 'Lunch, extra',
          entryCount: 2,
          kind: TransactionSummaryKind.expense,
          amountMinor: BigInt.from(3200),
          categoryName: 'Food',
          accountName: 'Cash',
        ),
      ],
      l10n: l10n,
    );

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('date,kind,amount,category,account,description'));
    expect(csv, contains('expense'));
    expect(csv, contains('32.00'));
    expect(csv, contains('餐饮'));
    expect(csv, contains('"Lunch, extra"'));
  });

  test('csv parser reads WeChat and Ledgerly bills', () {
    const wechat = '''
微信支付账单明细,,,,
交易时间,交易类型,交易对方,商品,收/支,金额(元)
2026-08-01 12:00:00,商户消费,星巴克,拿铁,支出,32.00
2026-08-01 13:00:00,转账,自己,还款,不计收支,100.00
''';
    const ledgerly = '''
date,kind,amount,category,account,description
2026-08-02T04:00:00.000Z,income,1000.00,工资收入,现金,Salary
''';
    const parser = CsvBillParser();
    final wechatDrafts = parser.parse(wechat);
    expect(wechatDrafts, hasLength(1));
    expect(wechatDrafts.single.description, '拿铁');
    expect(wechatDrafts.single.amountMinor, BigInt.from(3200));
    expect(wechatDrafts.single.kind, TransactionSummaryKind.expense);

    final imported = parser.parse(ledgerly).single;
    expect(imported.kind, TransactionSummaryKind.income);
    expect(imported.amountMinor, BigInt.from(100000));
  });

  test('import category matching prefers contains for Alipay labels', () {
    final id = matchImportCategoryId(
      kind: 'expense',
      rawCategory: '餐饮美食',
      categories: const [
        ImportCategory(id: 'food', name: 'Food', type: 'expense'),
        ImportCategory(id: 'other', name: 'Other Expense', type: 'expense'),
      ],
      localize: (name) => localizedLedgerName(l10n, name),
    );
    expect(id, 'food');
  });

  test('recurring dates clamp to 28 and detect due items', () {
    expect(
      RecurringDate.nextMonthlyDate(
        from: DateTime(2026, 8, 22),
        dayOfMonth: 15,
      ),
      '2026-09-15',
    );
    expect(
      RecurringDate.nextMonthlyDate(
        from: DateTime(2026, 8, 10),
        dayOfMonth: 15,
      ),
      '2026-08-15',
    );
    expect(RecurringDate.advanceOneMonth('2026-01-28', 28), '2026-02-28');
    expect(RecurringDate.advanceOneMonth('2026-01-31', 31), '2026-02-28');
    expect(
      RecurringDate.nextMonthlyDate(
        from: DateTime(2026, 2, 10),
        dayOfMonth: 31,
      ),
      '2026-02-28',
    );
    expect(RecurringDate.isDue('2026-08-22', DateTime(2026, 8, 22)), isTrue);
    expect(RecurringDate.isDue('2026-08-23', DateTime(2026, 8, 22)), isFalse);
  });

  test('budget spent includes child categories', () {
    final budget = LocalBudgetRecord(
      id: 'b1',
      bookId: defaultBookId,
      name: '餐饮',
      amountMinor: BigInt.from(100000),
      categoryAccountId: 'food',
      createdAt: DateTime.utc(2026, 8, 1),
    );
    final spent = spentForBudget(
      budget: budget,
      parentById: const {'meals': 'food', 'food': null},
      transactions: [
        TransactionSummary(
          id: '1',
          occurredAt: DateTime.utc(2026, 8, 4),
          description: 'Lunch',
          entryCount: 2,
          kind: TransactionSummaryKind.expense,
          amountMinor: BigInt.from(3200),
          categoryAccountId: 'meals',
        ),
        TransactionSummary(
          id: '2',
          occurredAt: DateTime.utc(2026, 8, 4),
          description: 'Salary',
          entryCount: 2,
          kind: TransactionSummaryKind.income,
          amountMinor: BigInt.from(100000),
          categoryAccountId: 'salary',
        ),
      ],
    );
    expect(spent, BigInt.from(3200));
  });

  test('app lock stores a PIN and requires it to unlock', () async {
    final controller = AppLockController(store: MemoryAppLockStore());
    await controller.load();
    expect(controller.enabled, isFalse);
    expect(controller.locked, isFalse);

    await controller.enable('1234');
    expect(controller.enabled, isTrue);
    expect(controller.locked, isFalse);

    controller.lock();
    expect(controller.locked, isTrue);
    expect(await controller.unlock('0000'), isFalse);
    expect(controller.locked, isTrue);
    expect(await controller.unlock('1234'), isTrue);
    expect(controller.locked, isFalse);
    expect(await controller.disable('1234'), isTrue);
    expect(controller.enabled, isFalse);
  });

  test('recurring scheduler posts due local rules', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LedgerRepository(db, deviceIdLoader: () async => 'test-device');
    await repo.seedIfEmpty();
    final rules = LocalRecurringRepository(db);
    final inserted = await rules.insert(
      bookId: defaultBookId,
      name: '地铁',
      kind: 'expense',
      amountMinor: BigInt.from(600),
      categoryAccountId: accountKeyFood(defaultBookId),
      accountId: accountKeyCash(defaultBookId),
      dayOfMonth: 1,
    );
    await db.customStatement(
      'UPDATE local_recurring_rules SET next_run_date = ? WHERE id = ?',
      ['2026-08-01', inserted.id],
    );

    final posted = await RecurringScheduler(
      rules: rules,
      ledger: LedgerAppService(repo),
      repository: repo,
    ).catchUp(now: DateTime(2026, 8, 22));

    expect(posted, greaterThanOrEqualTo(1));
    final summaries = await repo.watchSummariesSync(defaultBookId);
    expect(summaries.any((tx) => tx.description == '地铁'), isTrue);
    final updated = (await rules.list(defaultBookId)).single;
    expect(updated.nextRunDate.compareTo('2026-08-01'), greaterThan(0));

    final again = await RecurringScheduler(
      rules: rules,
      ledger: LedgerAppService(repo),
      repository: repo,
    ).catchUp(now: DateTime(2026, 8, 22));
    expect(again, 0);
  });

  test('csv parser skips refunds, reads Alipay tabs, and uses counterparty', () {
    const alipay = '''
支付宝交易记录明细查询
交易创建时间\t交易对方\t商品名称\t金额（元）\t收/支\t交易状态
2026-08-01 08:00:00\t星巴克\t\t32.00\t支出\t交易成功
2026-08-01 09:00:00\t退款商户\t拿铁\t32.00\t支出\t退款成功
''';
    const parser = CsvBillParser();
    final drafts = parser.parse(alipay);
    expect(drafts, hasLength(1));
    expect(drafts.single.description, '星巴克');
    expect(drafts.single.amountMinor, BigInt.from(3200));
  });

  test('csv decoder reads GBK Alipay exports', () {
    final csv = '交易时间,金额,收/支\n2026-08-03 10:00:00,12.50,支出\n';
    final drafts = const CsvBillParser().parse(decodeBillCsvBytes(gbk.encode(csv)));
    expect(drafts, hasLength(1));
    expect(drafts.single.amountMinor, BigInt.from(1250));
  });

  test('import duplicates are unchecked', () {
    final draft = ImportDraft(
      occurredAt: DateTime(2026, 8, 4, 12),
      kind: TransactionSummaryKind.expense,
      amountMinor: BigInt.from(3200),
      description: '星巴克拿铁',
    );
    markDuplicateImportDrafts(
      drafts: [draft],
      existing: [
        TransactionSummary(
          id: '1',
          occurredAt: DateTime(2026, 8, 4, 9),
          description: '星巴克拿铁',
          entryCount: 2,
          kind: TransactionSummaryKind.expense,
          amountMinor: BigInt.from(3200),
        ),
      ],
    );
    expect(draft.duplicate, isTrue);
    expect(draft.selected, isFalse);
  });

  test('app lock can unlock with biometrics then still require PIN later', () async {
    final biometrics = MemoryBiometricAuth();
    final controller = AppLockController(
      store: MemoryAppLockStore(pin: '1234', biometricEnabled: true),
      biometric: biometrics,
    );
    await controller.load();
    expect(controller.locked, isTrue);
    expect(controller.biometricEnabled, isTrue);
    expect(
      await controller.unlockWithBiometrics(reason: 'unlock'),
      isTrue,
    );
    expect(controller.locked, isFalse);
    expect(biometrics.authenticateCount, 1);

    controller.lock();
    biometrics.succeeds = false;
    expect(
      await controller.unlockWithBiometrics(reason: 'unlock'),
      isFalse,
    );
    expect(controller.locked, isTrue);
    expect(await controller.unlock('1234'), isTrue);
  });
}
