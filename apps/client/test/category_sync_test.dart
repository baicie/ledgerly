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
    });
    final localCategory =
        (await repository.listCategories(defaultBookId, 'expense'))
            .singleWhere((category) => category.id == categoryId);
    expect(localCategory.name, '宠物与园艺');
    expect(await repository.listPending(defaultBookId), isEmpty);
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
