import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Books,
    Accounts,
    Transactions,
    TransactionEntries,
    PendingMutations,
    SyncStates,
    SyncConflicts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  AppDatabase.forTesting(super.executor);

  static QueryExecutor _open() {
    return driftDatabase(
      name: 'ledgerly',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }

  @override
  int get schemaVersion => 7;

  static const aiInsightsTableDdl = '''
CREATE TABLE IF NOT EXISTS ai_insights (
  id TEXT NOT NULL PRIMARY KEY,
  book_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  period_key TEXT NOT NULL,
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL,
  model TEXT NOT NULL,
  prompt_version TEXT NOT NULL,
  input_hash TEXT NOT NULL,
  status TEXT NOT NULL,
  headline TEXT,
  body_json TEXT NOT NULL,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  generated_at INTEGER NOT NULL
);
''';

  static const localBudgetsTableDdl = '''
CREATE TABLE IF NOT EXISTS local_budgets (
  id TEXT NOT NULL PRIMARY KEY,
  book_id TEXT NOT NULL,
  name TEXT NOT NULL,
  amount_minor TEXT NOT NULL,
  category_account_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
''';

  static const localRecurringTableDdl = '''
CREATE TABLE IF NOT EXISTS local_recurring_rules (
  id TEXT NOT NULL PRIMARY KEY,
  book_id TEXT NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  amount_minor TEXT NOT NULL,
  category_account_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  day_of_month INTEGER NOT NULL,
  next_run_date TEXT NOT NULL,
  active INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
''';

  static const localAttachmentsTableDdl = '''
CREATE TABLE IF NOT EXISTS local_attachments (
  id TEXT NOT NULL PRIMARY KEY,
  book_id TEXT NOT NULL,
  transaction_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  mime TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
''';

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(aiInsightsTableDdl);
          await customStatement(localBudgetsTableDdl);
          await customStatement(localRecurringTableDdl);
          await customStatement(localAttachmentsTableDdl);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(transactions, transactions.deletedAt);
            await m.createTable(pendingMutations);
            await m.createTable(syncStates);
            await m.createTable(syncConflicts);
          }
          if (from < 3) {
            await m.addColumn(syncStates, syncStates.remoteBookId);
          }
          if (from < 4) {
            await m.alterTable(TableMigration(syncStates));
          }
          if (from < 5) {
            await m.addColumn(accounts, accounts.parentAccountId);
          }
          if (from < 6) {
            await customStatement(aiInsightsTableDdl);
          }
          if (from < 7) {
            await customStatement(localBudgetsTableDdl);
            await customStatement(localRecurringTableDdl);
            await customStatement(localAttachmentsTableDdl);
          }
        },
      );
}
