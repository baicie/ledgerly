import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'v3 migration physically removes legacy token columns and values',
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
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        description TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
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
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('access_token')),
      );
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('refresh_token')),
      );
      expect(
        schema.read<String>('sql'),
        isNot(contains('legacy-access-secret')),
      );
      expect(
        schema.read<String>('sql'),
        isNot(contains('legacy-refresh-secret')),
      );
    },
  );

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
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        description TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
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

  test('v5 migration creates local ai_insights cache table', () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency_code TEXT NOT NULL,
        parent_account_id TEXT
      );
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        description TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
      );
      PRAGMA user_version = 5;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_insights'",
        )
        .get();
    final columns =
        await db.customSelect("PRAGMA table_info('ai_insights')").get();

    expect(tables, isNotEmpty);
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll([
        'id',
        'book_id',
        'kind',
        'period_key',
        'input_hash',
        'status',
        'body_json',
        'prompt_tokens',
        'completion_tokens',
      ]),
    );
  });

  test('v6 migration creates local daily-tool tables', () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency_code TEXT NOT NULL,
        parent_account_id TEXT
      );
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        description TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
      );
      PRAGMA user_version = 6;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('local_budgets', 'local_recurring_rules', 'local_attachments')",
        )
        .get();
    expect(
      tables.map((row) => row.read<String>('name')),
      containsAll([
        'local_budgets',
        'local_recurring_rules',
        'local_attachments',
      ]),
    );
  });

  test('v10 migration adds persisted cloud upload state', () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE local_attachments (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      INSERT INTO local_attachments (
        id, book_id, transaction_id, file_name, mime, relative_path, created_at
      ) VALUES (
        'attachment-1', 'book-1', 'transaction-1', 'receipt.jpg',
        'image/jpeg', 'attachments/attachment-1', 1700000000
      );
      PRAGMA user_version = 9;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final columns =
        await db.customSelect("PRAGMA table_info('local_attachments')").get();
    final row = await db.customSelect(
        'SELECT * FROM local_attachments WHERE id = ?',
        variables: [
          const Variable<String>('attachment-1'),
        ]).getSingle();

    expect(
      columns.map((column) => column.read<String>('name')),
      containsAll([
        'cloud_upload_status',
        'remote_attachment_id',
        'remote_object_key',
        'remote_upload_error',
      ]),
    );
    expect(row.read<String>('cloud_upload_status'), 'local');
  });

  test('v11 migration adds persisted retry backoff', () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE local_attachments (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        cloud_upload_status TEXT NOT NULL DEFAULT 'local',
        remote_attachment_id TEXT,
        remote_object_key TEXT,
        remote_upload_error TEXT,
        created_at INTEGER NOT NULL
      );
      INSERT INTO local_attachments (
        id, book_id, transaction_id, file_name, mime, relative_path, created_at
      ) VALUES (
        'attachment-1', 'book-1', 'transaction-1', 'receipt.jpg',
        'image/jpeg', 'attachments/attachment-1', 1700000000
      );
      PRAGMA user_version = 10;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final columns =
        await db.customSelect("PRAGMA table_info('local_attachments')").get();
    final row = await db.customSelect(
        'SELECT * FROM local_attachments WHERE id = ?',
        variables: [
          const Variable<String>('attachment-1'),
        ]).getSingle();

    expect(
      columns.map((column) => column.read<String>('name')),
      containsAll(['retry_attempt_count', 'next_retry_at']),
    );
    expect(row.read<int>('retry_attempt_count'), 0);
    expect(row.read<int?>('next_retry_at'), isNull);
  });

  test('v12 migration adds persisted multipart session hints', () async {
    final underlying = sqlite3.openInMemory();
    underlying.execute('''
      CREATE TABLE local_attachments (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        cloud_upload_status TEXT NOT NULL DEFAULT 'local',
        remote_attachment_id TEXT,
        remote_object_key TEXT,
        remote_upload_error TEXT,
        retry_attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER,
        created_at INTEGER NOT NULL
      );
      INSERT INTO local_attachments (
        id, book_id, transaction_id, file_name, mime, relative_path, created_at
      ) VALUES (
        'attachment-1', 'book-1', 'transaction-1', 'receipt.jpg',
        'image/jpeg', 'attachments/attachment-1', 1700000000
      );
      PRAGMA user_version = 11;
    ''');
    final db = AppDatabase.forTesting(NativeDatabase.opened(underlying));
    addTearDown(db.close);

    final columns =
        await db.customSelect("PRAGMA table_info('local_attachments')").get();
    final row = await db.customSelect(
        'SELECT * FROM local_attachments WHERE id = ?',
        variables: [
          const Variable<String>('attachment-1'),
        ]).getSingle();

    expect(
      columns.map((column) => column.read<String>('name')),
      containsAll(['remote_upload_mode', 'remote_part_size_bytes']),
    );
    expect(row.read<String?>('remote_upload_mode'), isNull);
    expect(row.read<int?>('remote_part_size_bytes'), isNull);
  });
}
