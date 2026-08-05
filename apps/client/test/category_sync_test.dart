import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/sync_service.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/sync_api.dart';
import 'package:ledgerly_client/domain/ids.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  test('sync rewrites category ids and applies pulled account changes',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-sync-device',
    );
    await repository.seedIfEmpty();
    final categoryId = await LedgerAppService(repository).createCategory(
      name: '宠物用品',
      type: 'expense',
      parentCategoryId: accountKeyFood(defaultBookId),
    );
    final remoteCategoryId = categoryId.replaceFirst(
      '$defaultBookId:',
      'remote-book:',
    );

    Map<String, dynamic>? pushedBody;
    final adapter = _CallbackAdapter();
    adapter.handler = (request) async {
      if (request.path.endsWith('/sync/push')) {
        pushedBody = Map<String, dynamic>.from(request.data as Map);
        final mutations = (pushedBody!['mutations'] as List).cast<Map>();
        return _jsonResponse(200, {
          'receipts': [
            for (final mutation in mutations)
              {
                'mutationId': mutation['mutationId'],
                'status': 'applied',
                'resultCode': 'OK',
                'entityVersion': 1,
              },
          ],
        });
      }
      if (request.path.endsWith('/sync/pull')) {
        return _jsonResponse(200, {
          'nextCursor': '7',
          'hasMore': false,
          'changes': [
            {
              'sequence': '7',
              'commitId': 'account-commit',
              'entityType': 'account',
              'entityId': remoteCategoryId,
              'operation': 'upsert',
              'version': 1,
              'payload': {
                'name': '宠物与园艺',
                'accountType': 'expense',
                'currency': 'CNY',
                'parentAccountId': 'remote-book:acc_transport',
              },
            },
          ],
        });
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    };
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'remote-book', plan: 'free');
    await auth.restore();

    final result = await SyncService(
      repository,
      SyncApi(dio: dio),
      auth,
    ).syncNow();

    expect(result.ok, isTrue);
    final mutations = (pushedBody!['mutations'] as List).cast<Map>();
    expect(mutations, hasLength(1));
    expect(mutations.single['entityType'], 'account');
    expect(mutations.single['entityId'], remoteCategoryId);
    expect(mutations.single['payload'], {
      'name': '宠物用品',
      'accountType': 'expense',
      'currency': 'CNY',
      'parentAccountId': 'remote-book:acc_food',
    });
    final localCategory =
        (await repository.listCategories(defaultBookId, 'expense'))
            .singleWhere((category) => category.id == categoryId);
    expect(localCategory.name, '宠物与园艺');
    expect(
      localCategory.parentAccountId,
      accountKeyTransport(defaultBookId),
    );
    expect(await repository.listPending(defaultBookId), isEmpty);
  });

  test('sync retries a rejected category as a root category', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-repair-device',
    );
    await repository.seedIfEmpty();
    final service = LedgerAppService(repository);
    final categoryId = await service.createCategory(
      name: '宠物用品',
      type: 'expense',
      parentCategoryId: accountKeyFood(defaultBookId),
    );
    await service.createExpense(
      expenseAccountId: categoryId,
      fundingAccountId: accountKeyCash(defaultBookId),
      amountMinor: BigInt.from(1200),
      description: '宠物用品',
    );

    final pushedBatches = <List<Map<String, dynamic>>>[];
    final adapter = _CallbackAdapter();
    adapter.handler = (request) async {
      if (request.path.endsWith('/sync/push')) {
        final body = Map<String, dynamic>.from(request.data as Map);
        final mutations = (body['mutations'] as List)
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        pushedBatches.add(mutations);
        final rejected = pushedBatches.length == 1;
        return _jsonResponse(200, {
          'receipts': [
            for (final mutation in mutations)
              {
                'mutationId': mutation['mutationId'],
                'status': rejected ? 'rejected' : 'applied',
                'resultCode': rejected
                    ? mutation['entityType'] == 'account'
                        ? 'INVALID_CATEGORY_PARENT'
                        : 'ACCOUNT_NOT_FOUND'
                    : 'OK',
                'entityVersion': rejected ? null : 1,
              },
          ],
        });
      }
      if (request.path.endsWith('/sync/pull')) {
        return _jsonResponse(200, {
          'nextCursor': '1',
          'hasMore': false,
          'changes': const [],
        });
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    };
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'remote-book', plan: 'free');
    await auth.restore();

    final result = await SyncService(
      repository,
      SyncApi(dio: dio),
      auth,
    ).syncNow();

    expect(result.ok, isTrue);
    expect(pushedBatches, hasLength(2));
    expect(pushedBatches.first, hasLength(2));
    expect(pushedBatches.last, hasLength(2));
    final firstAccount = pushedBatches.first
        .singleWhere((mutation) => mutation['entityType'] == 'account');
    final retriedAccount = pushedBatches.last
        .singleWhere((mutation) => mutation['entityType'] == 'account');
    final firstTransaction = pushedBatches.first
        .singleWhere((mutation) => mutation['entityType'] == 'transaction');
    final retriedTransaction = pushedBatches.last
        .singleWhere((mutation) => mutation['entityType'] == 'transaction');
    expect(
      (firstAccount['payload'] as Map)['parentAccountId'],
      'remote-book:acc_food',
    );
    expect(
      (retriedAccount['payload'] as Map)['parentAccountId'],
      isNull,
    );
    expect(
      retriedAccount['mutationId'],
      isNot(firstAccount['mutationId']),
    );
    expect(
      retriedTransaction['mutationId'],
      isNot(firstTransaction['mutationId']),
    );
    final category = (await repository.listCategories(defaultBookId, 'expense'))
        .singleWhere((account) => account.id == categoryId);
    expect(category.parentAccountId, isNull);
    expect(await repository.watchSummariesSync(defaultBookId), hasLength(1));
    expect(await repository.listPending(defaultBookId), isEmpty);
    expect(await repository.listConflicts(defaultBookId), isEmpty);
  });

  test('sync renews later edits after a category create is rejected', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-edit-repair-device',
    );
    await repository.seedIfEmpty();
    final service = LedgerAppService(repository);
    final categoryId = await service.createCategory(
      name: '宠物用品',
      type: 'expense',
      parentCategoryId: accountKeyFood(defaultBookId),
    );
    await service.renameCategory(categoryId: categoryId, name: '宠物与园艺');

    final pushedBatches = <List<Map<String, dynamic>>>[];
    final adapter = _CallbackAdapter();
    adapter.handler = (request) async {
      if (request.path.endsWith('/sync/push')) {
        final body = Map<String, dynamic>.from(request.data as Map);
        final mutations = (body['mutations'] as List)
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        pushedBatches.add(mutations);
        return _jsonResponse(200, {
          'receipts': [
            for (var index = 0; index < mutations.length; index++)
              {
                'mutationId': mutations[index]['mutationId'],
                'status': pushedBatches.length == 1 ? 'rejected' : 'applied',
                'resultCode': pushedBatches.length == 1
                    ? index == 0
                        ? 'INVALID_CATEGORY_PARENT'
                        : 'ACCOUNT_NOT_FOUND'
                    : 'OK',
                'entityVersion': pushedBatches.length == 1 ? null : index + 1,
              },
          ],
        });
      }
      if (request.path.endsWith('/sync/pull')) {
        return _jsonResponse(200, {
          'nextCursor': '1',
          'hasMore': false,
          'changes': const [],
        });
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    };
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'remote-book', plan: 'free');
    await auth.restore();

    final result = await SyncService(
      repository,
      SyncApi(dio: dio),
      auth,
    ).syncNow();

    expect(result.ok, isTrue);
    expect(pushedBatches, hasLength(2));
    expect(pushedBatches.first, hasLength(2));
    expect(pushedBatches.last, hasLength(2));
    for (var index = 0; index < 2; index++) {
      expect(
        pushedBatches.last[index]['mutationId'],
        isNot(pushedBatches.first[index]['mutationId']),
      );
      expect(
        (pushedBatches.last[index]['payload'] as Map)['parentAccountId'],
        isNull,
      );
    }
    final category = (await repository.listCategories(defaultBookId, 'expense'))
        .singleWhere((account) => account.id == categoryId);
    expect(category.name, '宠物与园艺');
    expect(category.parentAccountId, isNull);
    expect(await repository.listPending(defaultBookId), isEmpty);
  });

  test('sync rejects a malformed remote category parent without advancing',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-malformed-device',
    );
    await repository.seedIfEmpty();

    final adapter = _CallbackAdapter();
    adapter.handler = (request) async {
      if (request.path.endsWith('/sync/pull')) {
        return _jsonResponse(200, {
          'nextCursor': '9',
          'hasMore': false,
          'changes': [
            {
              'sequence': '9',
              'commitId': 'malformed-account',
              'entityType': 'account',
              'entityId': 'remote-book:acc_food',
              'operation': 'upsert',
              'version': 2,
              'payload': {
                'name': 'Remote Food',
                'accountType': 'expense',
                'currency': 'CNY',
                'parentAccountId': 42,
              },
            },
          ],
        });
      }
      throw StateError('Unexpected request: ${request.method} ${request.path}');
    };
    final dio = Dio()..httpClientAdapter = adapter;
    final auth = FakeAuthGateway()
      ..restoreResult = const AuthSession(bookId: 'remote-book', plan: 'free');
    await auth.restore();

    final result = await SyncService(
      repository,
      SyncApi(dio: dio),
      auth,
    ).syncNow();

    expect(result.ok, isFalse);
    expect(result.message, contains('parentAccountId'));
    expect((await repository.syncState(defaultBookId))?.cursor, 0);
    final food = (await repository.listCategories(defaultBookId, 'expense'))
        .singleWhere((account) => account.id == accountKeyFood(defaultBookId));
    expect(food.name, 'Food');
  });
}

ResponseBody _jsonResponse(int status, Object body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

typedef _AdapterHandler = Future<ResponseBody> Function(RequestOptions request);

class _CallbackAdapter implements HttpClientAdapter {
  _AdapterHandler? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final callback = handler;
    if (callback == null) {
      throw StateError('No handler for ${options.method} ${options.path}');
    }
    return callback(options);
  }

  @override
  void close({bool force = false}) {}
}
