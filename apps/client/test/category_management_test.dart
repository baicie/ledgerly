import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('seeds a stable two-level default category taxonomy', () async {
    final categories = (await repository.listAccounts(defaultBookId))
        .where(
          (account) => account.type == 'expense' || account.type == 'income',
        )
        .toList();
    final byId = {for (final category in categories) category.id: category};
    final foodId = accountId(defaultBookId, 'acc_food');
    final mealsId = accountId(defaultBookId, 'acc_food_meals');
    final investmentId = accountId(defaultBookId, 'acc_investment_income');
    final interestId = accountId(
      defaultBookId,
      'acc_investment_income_interest',
    );

    expect(categories, hasLength(36));
    expect(byId[foodId]?.parentAccountId, isNull);
    expect(byId[mealsId]?.parentAccountId, foodId);
    expect(byId[investmentId]?.parentAccountId, isNull);
    expect(byId[interestId]?.parentAccountId, investmentId);
  });

  test('backfills new defaults without overwriting an existing category',
      () async {
    await database.close();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.into(database.books).insert(
          BooksCompanion.insert(
            id: defaultBookId,
            name: 'Personal',
            currencyCode: 'CNY',
            createdAt: DateTime.utc(2026),
          ),
        );
    await database.into(database.accounts).insert(
          AccountsCompanion.insert(
            id: accountKeyFood(defaultBookId),
            bookId: defaultBookId,
            name: '家庭餐食',
            type: 'expense',
            currencyCode: 'CNY',
          ),
        );
    repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-test-device',
    );

    await repository.seedIfEmpty();
    await repository.seedIfEmpty();

    final categories = await repository.listCategories(
      defaultBookId,
      'expense',
    );
    expect(
      categories
          .singleWhere(
            (category) => category.id == accountKeyFood(defaultBookId),
          )
          .name,
      '家庭餐食',
    );
    expect(
      categories.where(
        (category) => category.id == accountId(defaultBookId, 'acc_food_meals'),
      ),
      hasLength(1),
    );
  });

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
    expect(created.parentAccountId, isNull);
  });

  test('creates a second-level category below a matching root', () async {
    final categoryId = await service.createCategory(
      name: '工作午餐',
      type: 'expense',
      parentCategoryId: accountKeyFood(defaultBookId),
    );

    final created = (await repository.listCategories(defaultBookId, 'expense'))
        .singleWhere((category) => category.id == categoryId);
    expect(created.parentAccountId, accountKeyFood(defaultBookId));

    final pending = await repository.listPending(defaultBookId);
    expect(jsonDecode(pending.single.payloadJson), {
      'name': '工作午餐',
      'accountType': 'expense',
      'currency': 'CNY',
      'parentAccountId': accountKeyFood(defaultBookId),
    });
  });

  test('rejects a third category level and cross-type parent', () async {
    final childId = await service.createCategory(
      name: '工作午餐',
      type: 'expense',
      parentCategoryId: accountKeyFood(defaultBookId),
    );

    expect(
      () => service.createCategory(
        name: '周一午餐',
        type: 'expense',
        parentCategoryId: childId,
      ),
      throwsA(isA<CategoryValidationException>()),
    );
    expect(
      () => service.createCategory(
        name: '错误收入分类',
        type: 'income',
        parentCategoryId: accountKeyFood(defaultBookId),
      ),
      throwsA(isA<CategoryValidationException>()),
    );
  });

  test('rejects duplicate names within the same category type', () async {
    await service.createCategory(name: '专项补贴', type: 'income');

    expect(
      () => service.createCategory(name: ' 专项补贴 ', type: 'income'),
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
      'parentAccountId': null,
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
      'parentAccountId': null,
    });
  });
}
