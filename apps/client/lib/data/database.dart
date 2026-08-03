import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Books, Accounts, Transactions, TransactionEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  static QueryExecutor _open() {
    return driftDatabase(name: 'ledgerly');
  }

  @override
  int get schemaVersion => 1;
}
