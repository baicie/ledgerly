import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ledger_app_service.dart';
import '../application/sync_service.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_controller.dart';
import '../auth/platform_session_store.dart';
import '../auth/session_store.dart';
import '../config/api_endpoint.dart';
import '../config/api_endpoint_controller.dart';
import '../data/database.dart';
import '../data/ledger_repository.dart';
import '../data/sync_api.dart';
import '../domain/ids.dart';
import '../domain/default_categories.dart';
import '../l10n/l10n.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

const _localSessionScope = 'ledgerly-local';

final apiEndpointProvider = Provider<ApiEndpoint?>((ref) => null);

final apiEndpointControllerProvider = Provider<ApiEndpointController>((ref) {
  throw StateError('ApiEndpointController has not been configured.');
});

final sessionStoreProvider = Provider<SessionStore>((ref) {
  final endpoint = ref.watch(apiEndpointProvider);
  return createPlatformSessionStore(endpoint?.baseUrl ?? _localSessionScope);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final endpoint = ref.watch(apiEndpointProvider);
  if (endpoint == null) {
    throw StateError('Remote authentication is unavailable in local mode.');
  }
  final repository = AuthRepository(
    endpoint: endpoint,
    sessionStore: ref.watch(sessionStoreProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  if (ref.watch(apiEndpointProvider) == null) {
    return AuthController.local();
  }
  final controller = AuthController(ref.watch(authRepositoryProvider));
  unawaited(controller.restore());
  return controller;
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  final sessionStore = ref.watch(sessionStoreProvider);
  return LedgerRepository(
    ref.watch(databaseProvider),
    deviceIdLoader: sessionStore.getOrCreateDeviceId,
  );
});

final ledgerAppServiceProvider = Provider<LedgerAppService>((ref) {
  return LedgerAppService(ref.watch(ledgerRepositoryProvider));
});

final syncApiProvider = Provider<SyncApi>((ref) {
  return SyncApi(
    dio: ref.watch(authRepositoryProvider).authenticatedClient,
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(ledgerRepositoryProvider),
    ref.watch(syncApiProvider),
    ref.watch(authRepositoryProvider),
  );
});

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

({DateTime start, DateTime end}) monthUtcRange(DateTime month) {
  return (
    start: DateTime(month.year, month.month).toUtc(),
    end: DateTime(month.year, month.month + 1).toUtc(),
  );
}

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
  final range = monthUtcRange(month);
  return repo.watchSummariesSync(
    defaultBookId,
    monthStart: range.start,
    monthEnd: range.end,
  );
});

class AccountBalanceRow {
  AccountBalanceRow({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.parentAccountId,
  });
  final String id;
  final String name;
  final String type;
  final BigInt balance;
  final String? parentAccountId;
}

class CategoryAccountRow {
  const CategoryAccountRow({
    required this.id,
    required this.name,
    required this.type,
    this.parentAccountId,
  });

  final String id;
  final String name;
  final String type;
  final String? parentAccountId;
}

final categoryAccountsProvider =
    FutureProvider.family<List<CategoryAccountRow>, String>((ref, type) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  await repo.seedIfEmpty();
  final accounts = await repo.listCategories(defaultBookId, type);
  final rows = accounts
      .map(
        (account) => CategoryAccountRow(
          id: account.id,
          name: account.name,
          type: account.type,
          parentAccountId: account.parentAccountId,
        ),
      )
      .toList();
  final byId = {for (final row in rows) row.id: row};
  rows.sort((left, right) {
    final leftRoot = byId[left.parentAccountId] ?? left;
    final rightRoot = byId[right.parentAccountId] ?? right;
    final rootOrder = defaultCategorySortOrder(leftRoot.name)
        .compareTo(defaultCategorySortOrder(rightRoot.name));
    if (rootOrder != 0) return rootOrder;
    if (left.parentAccountId == null && right.parentAccountId != null) {
      return -1;
    }
    if (left.parentAccountId != null && right.parentAccountId == null) return 1;
    final categoryOrder = defaultCategorySortOrder(left.name)
        .compareTo(defaultCategorySortOrder(right.name));
    if (categoryOrder != 0) return categoryOrder;
    return left.name.compareTo(right.name);
  });
  return rows;
});

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
        parentAccountId: a.parentAccountId,
      ),
    );
  }
  return rows;
});

class CategoryAmount {
  CategoryAmount({
    required this.name,
    required this.amount,
    required this.transactionCount,
  });

  final String name;
  final BigInt amount;
  final int transactionCount;
}

final categoryReportProvider =
    FutureProvider<List<CategoryAmount>>((ref) async {
  final transactions = await ref.watch(monthTransactionsProvider.future);
  final amounts = <String, BigInt>{};
  final counts = <String, int>{};
  for (final transaction in transactions) {
    if (transaction.kind != TransactionSummaryKind.expense) continue;
    final category = transaction.categoryName ?? 'Other';
    amounts.update(
      category,
      (amount) => amount + transaction.amountMinor,
      ifAbsent: () => transaction.amountMinor,
    );
    counts.update(category, (count) => count + 1, ifAbsent: () => 1);
  }
  final rows = amounts.entries
      .map(
        (entry) => CategoryAmount(
          name: entry.key,
          amount: entry.value,
          transactionCount: counts[entry.key] ?? 0,
        ),
      )
      .toList();
  rows.sort((a, b) => b.amount.compareTo(a.amount));
  return rows;
});

class MonthlyLedgerSummary {
  MonthlyLedgerSummary({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.transactionCount,
  });

  final BigInt incomeMinor;
  final BigInt expenseMinor;
  final int transactionCount;
  BigInt get balanceMinor => incomeMinor - expenseMinor;
}

final monthlyLedgerSummaryProvider =
    FutureProvider<MonthlyLedgerSummary>((ref) async {
  final transactions = await ref.watch(monthTransactionsProvider.future);
  var income = BigInt.zero;
  var expense = BigInt.zero;
  for (final transaction in transactions) {
    switch (transaction.kind) {
      case TransactionSummaryKind.income:
        income += transaction.amountMinor;
      case TransactionSummaryKind.expense:
        expense += transaction.amountMinor;
      case TransactionSummaryKind.transfer:
      case TransactionSummaryKind.adjustment:
        break;
    }
  }
  return MonthlyLedgerSummary(
    incomeMinor: income,
    expenseMinor: expense,
    transactionCount: transactions.length,
  );
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
    label: state?.lastError == null
        ? L10n.current.syncReady
        : L10n.current.syncError,
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
          remoteVersion: c.remoteVersion,
        ),
      )
      .toList();
});

class SyncConflictItem {
  SyncConflictItem({
    required this.id,
    required this.entityId,
    required this.reason,
    required this.remoteVersion,
  });
  final String id;
  final String entityId;
  final String reason;
  final int? remoteVersion;
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
