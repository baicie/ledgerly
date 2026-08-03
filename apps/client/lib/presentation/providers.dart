import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ledger_app_service.dart';
import '../application/sync_service.dart';
import '../data/database.dart';
import '../data/ledger_repository.dart';
import '../data/sync_api.dart';
import '../domain/ids.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository(ref.watch(databaseProvider));
});

final ledgerAppServiceProvider = Provider<LedgerAppService>((ref) {
  return LedgerAppService(ref.watch(ledgerRepositoryProvider));
});

final syncApiProvider = Provider<SyncApi>((ref) => SyncApi());

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(ledgerRepositoryProvider),
    ref.watch(syncApiProvider),
  );
});

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final transactionListProvider =
    StreamProvider<List<TransactionSummary>>((ref) async* {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  yield* repo.watchSummaries(defaultBookId);
});

final monthTransactionsProvider =
    FutureProvider<List<TransactionSummary>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  await ref.watch(transactionListProvider.future);
  final month = ref.watch(selectedMonthProvider);
  final start = DateTime.utc(month.year, month.month);
  final end = DateTime.utc(month.year, month.month + 1);
  return repo.watchSummariesSync(
    defaultBookId,
    monthStart: start,
    monthEnd: end,
  );
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
  await ref.watch(transactionListProvider.future);
  final accounts = await repo.listAccounts(defaultBookId);
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

class SyncStatusView {
  const SyncStatusView({
    required this.label,
    required this.cursor,
    required this.pendingCount,
    this.lastError,
    this.remoteBookId,
  });
  final String label;
  final int cursor;
  final int pendingCount;
  final String? lastError;
  final String? remoteBookId;
}

final syncStatusProvider = FutureProvider<SyncStatusView>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  final state = await repo.syncState(defaultBookId);
  final pending = await repo.listPending(defaultBookId);
  return SyncStatusView(
    label: state?.lastError == null ? '就绪' : '出错',
    cursor: state?.cursor ?? 0,
    pendingCount: pending.length,
    lastError: state?.lastError,
    remoteBookId: state?.remoteBookId,
  );
});

final conflictsProvider = FutureProvider<List<SyncConflictItem>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  final rows = await repo.listConflicts(defaultBookId);
  return rows
      .map(
        (c) => SyncConflictItem(
          id: c.id,
          entityId: c.entityId,
          reason: c.reason,
        ),
      )
      .toList();
});

class SyncConflictItem {
  SyncConflictItem({
    required this.id,
    required this.entityId,
    required this.reason,
  });
  final String id;
  final String entityId;
  final String reason;
}

final exportCsvProvider = FutureProvider<String>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  final txs = await repo.watchSummariesSync(defaultBookId);
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
