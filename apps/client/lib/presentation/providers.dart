import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';

import '../application/ledger_app_service.dart';
import '../data/database.dart';
import '../data/ledger_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final testingDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  ref.onDispose(db.close);
  return db;
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository(ref.watch(databaseProvider));
});

final ledgerAppServiceProvider = Provider<LedgerAppService>((ref) {
  return LedgerAppService(ref.watch(ledgerRepositoryProvider));
});

final transactionListProvider =
    StreamProvider<List<TransactionSummary>>((ref) async* {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  yield* repo.watchSummaries('book_default');
});
