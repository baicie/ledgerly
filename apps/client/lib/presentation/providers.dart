import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class AccountBalanceRow {
  AccountBalanceRow({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
  });
  final String id;
  final String name;
  final String type;
  final BigInt balance;
}

final accountBalancesProvider =
    FutureProvider<List<AccountBalanceRow>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  // Rebuild when transactions change.
  await ref.watch(transactionListProvider.future);
  final accounts = await repo.listAccounts('book_default');
  final rows = <AccountBalanceRow>[];
  for (final a in accounts) {
    rows.add(
      AccountBalanceRow(
        id: a.id,
        name: a.name,
        type: a.type,
        balance: await repo.accountBalance(a.id),
      ),
    );
  }
  return rows;
});

class CategoryAmount {
  CategoryAmount({required this.name, required this.amount});
  final String name;
  final BigInt amount;
}

final categoryReportProvider = FutureProvider<List<CategoryAmount>>((ref) async {
  final balances = await ref.watch(accountBalancesProvider.future);
  return balances
      .where((b) => b.type == 'expense' && b.balance > BigInt.zero)
      .map((b) => CategoryAmount(name: b.name, amount: b.balance))
      .toList();
});

class SyncStatus {
  const SyncStatus({
    required this.label,
    required this.cursor,
    required this.pendingCount,
  });
  final String label;
  final int cursor;
  final int pendingCount;
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() =>
      const SyncStatus(label: '空闲', cursor: 0, pendingCount: 0);

  void markSynced() {
    state = SyncStatus(
      label: '已同步',
      cursor: state.cursor + 1,
      pendingCount: 0,
    );
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

class ConflictItem {
  ConflictItem({required this.entityId, required this.reason});
  final String entityId;
  final String reason;
}

class ConflictsNotifier extends Notifier<List<ConflictItem>> {
  @override
  List<ConflictItem> build() => [
        ConflictItem(entityId: 'tx_demo', reason: 'LEDGER_VERSION_CONFLICT'),
      ];

  void keepRemote(String entityId) {
    state = state.where((c) => c.entityId != entityId).toList();
  }
}

final conflictsProvider =
    NotifierProvider<ConflictsNotifier, List<ConflictItem>>(
  ConflictsNotifier.new,
);

final exportCsvProvider = FutureProvider<String>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  final txs = await repo.watchSummariesSync('book_default');
  final buf = StringBuffer('id,occurred_at,description,entry_count\n');
  for (final tx in txs) {
    buf.writeln(
      '${tx.id},${tx.occurredAt.toIso8601String()},"${tx.description ?? ''}",${tx.entryCount}',
    );
  }
  return buf.toString();
});

String formatMinor(BigInt minor) {
  final negative = minor.isNegative;
  final abs = minor.abs();
  final yuan = abs ~/ BigInt.from(100);
  final cents = abs % BigInt.from(100);
  return '${negative ? '-' : ''}$yuan.${cents.toString().padLeft(2, '0')}';
}
