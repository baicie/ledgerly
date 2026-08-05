import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';

void main() {
  late AppDatabase database;
  late LedgerRepository repository;
  late LedgerAppService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-test-device',
    );
    await repository.seedIfEmpty();
    service = LedgerAppService(repository);
  });

  tearDown(() => database.close());

  test('creates an expense category with a trimmed name', () async {
    final categoryId = await service.createCategory(
      name: '  日常用品  ',
      type: 'expense',
    );

    final categories = (await repository.listAccounts(defaultBookId))
        .where((account) => account.type == 'expense');
    final created =
        categories.singleWhere((account) => account.id == categoryId);
    expect(created.name, '日常用品');
  });

  test('rejects duplicate names within the same category type', () async {
    await service.createCategory(name: '奖金', type: 'income');

    expect(
      () => service.createCategory(name: ' 奖金 ', type: 'income'),
      throwsA(isA<CategoryValidationException>()),
    );
  });

  test('rejects a localized alias of a built-in category', () async {
    expect(
      () => service.createCategory(name: '餐饮', type: 'expense'),
      throwsA(isA<CategoryValidationException>()),
    );
  });

  test('allows the same category name across income and expense', () async {
    await service.createCategory(name: '其他', type: 'expense');
    final incomeId = await service.createCategory(name: '其他', type: 'income');

    final income = (await repository.listCategories(defaultBookId, 'income'))
        .singleWhere((category) => category.id == incomeId);
    expect(income.name, '其他');
  });

  test('renames a category without breaking historical transactions', () async {
    final categoryId = await service.createCategory(
      name: '早餐',
      type: 'expense',
    );
    await service.createExpense(
      expenseAccountId: categoryId,
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(1800),
      description: '豆浆油条',
    );

    await service.renameCategory(categoryId: categoryId, name: '早午晚餐');

    final renamed = (await repository.listAccounts(defaultBookId))
        .singleWhere((account) => account.id == categoryId);
    final summary = (await repository.watchSummariesSync(defaultBookId)).single;
    expect(renamed.name, '早午晚餐');
    expect(summary.categoryName, '早午晚餐');
  });

  test('queues a category before a transaction that references it', () async {
    final categoryId = await service.createCategory(
      name: '宠物用品',
      type: 'expense',
    );
    await service.createExpense(
      expenseAccountId: categoryId,
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(6600),
    );

    final pending = await repository.listPending(defaultBookId);
    expect(pending.map((mutation) => mutation.entityType), [
      'account',
      'transaction',
    ]);
    expect(pending.first.entityId, categoryId);
    expect(pending.first.operation, 'create');
    expect(jsonDecode(pending.first.payloadJson), {
      'name': '宠物用品',
      'accountType': 'expense',
      'currency': 'CNY',
    });
  });

  test('queues a category rename for synchronization', () async {
    final categoryId = await service.createCategory(
      name: '副业',
      type: 'income',
    );
    await service.renameCategory(categoryId: categoryId, name: '项目收入');

    final pending = await repository.listPending(defaultBookId);
    expect(pending.map((mutation) => mutation.operation), ['create', 'update']);
    expect(pending.last.entityType, 'account');
    expect(pending.last.entityId, categoryId);
    expect(jsonDecode(pending.last.payloadJson), {
      'name': '项目收入',
      'accountType': 'income',
      'currency': 'CNY',
    });
  });
}
