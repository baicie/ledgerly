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
  int get schemaVersion => 6;

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

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(aiInsightsTableDdl);
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
        },
      );
}
