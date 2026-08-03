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
    return driftDatabase(name: 'ledgerly');
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(transactions, transactions.deletedAt);
            await m.createTable(pendingMutations);
            await m.createTable(syncStates);
            await m.createTable(syncConflicts);
          }
        },
      );
}
