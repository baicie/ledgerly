import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v3 migration physically removes legacy token columns and values',
      () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE sync_states (
        book_id TEXT NOT NULL PRIMARY KEY,
        device_id TEXT NOT NULL,
        cursor INTEGER NOT NULL DEFAULT 0,
        access_token TEXT,
        refresh_token TEXT,
        remote_book_id TEXT,
        last_error TEXT,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency_code TEXT NOT NULL
      );
      INSERT INTO sync_states (
        book_id, device_id, cursor, access_token, refresh_token,
        remote_book_id, last_error, updated_at
      ) VALUES (
        'book-local', 'legacy-device', 42, 'legacy-access-secret',
        'legacy-refresh-secret', 'book-remote', NULL, 1700000000
      );
      PRAGMA user_version = 3;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final state = await db.select(db.syncStates).getSingle();
    final columns =
        await db.customSelect("PRAGMA table_info('sync_states')").get();
    final schema = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='sync_states'",
        )
        .getSingle();

    expect(state.cursor, 42);
    expect(state.remoteBookId, 'book-remote');
    expect(columns.map((row) => row.read<String>('name')),
        isNot(contains('access_token')));
    expect(columns.map((row) => row.read<String>('name')),
        isNot(contains('refresh_token')));
    expect(schema.read<String>('sql'), isNot(contains('legacy-access-secret')));
    expect(
        schema.read<String>('sql'), isNot(contains('legacy-refresh-secret')));
  });

  test('v4 migration adds nullable category parent account ids', () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency_code TEXT NOT NULL
      );
      INSERT INTO accounts (id, book_id, name, type, currency_code)
      VALUES ('book:acc_food', 'book', 'Food', 'expense', 'CNY');
      PRAGMA user_version = 4;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final account = await db.select(db.accounts).getSingle();
    final columns =
        await db.customSelect("PRAGMA table_info('accounts')").get();

    expect(account.parentAccountId, isNull);
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('parent_account_id'),
    );
  });
}
