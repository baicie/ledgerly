import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ledger_repository.dart';
import '../domain/ids.dart';
import '../presentation/providers.dart';
import 'ledger_app_service.dart';
import 'merchant_classifier.dart';
import '../../services/payment_notification_service.dart';

/// Reserved [LedgerTransaction.source] value for transactions created by
/// [AutoLedgerService] from captured payment notifications.
const String autoLedgerSource = 'auto_ledger';

/// Result of flushing one queued payment event into the ledger.
enum AutoLedgerOutcome { posted, duplicate, skipped }

/// Summary of a single sync cycle.
class AutoLedgerSyncReport {
  const AutoLedgerSyncReport({
    required this.posted,
    required this.duplicates,
    required this.skipped,
  });

  final int posted;
  final int duplicates;
  final int skipped;

  int get total => posted + duplicates + skipped;

  @override
  String toString() =>
      'AutoLedgerSyncReport(posted: $posted, duplicates: $duplicates, skipped: $skipped)';
}

/// Drains pending payment events into the ledger.
///
/// Pipeline:
/// 1. Read queued events from Android via [PaymentNotificationService].
/// 2. Drop noisy events (stale after 7 days).
/// 3. Skip duplicates that already exist in the ledger within the dedup
///    window (same platform, amount, merchant, and 60s window).
/// 4. Classify the merchant into a default category.
/// 5. Call [LedgerAppService.createExpense] / [createIncome] which writes
///    the transaction + pending mutation.
/// 6. Clear the native queue once each event has been handled.
class AutoLedgerService {
  AutoLedgerService({
    required this.repository,
    required this.ledger,
    required this.notifications,
    MerchantClassifier? classifier,
    Duration dedupWindow = const Duration(seconds: 60),
    Duration staleAfter = const Duration(days: 7),
    DateTime Function()? now,
  })  : classifier = classifier ?? const MerchantClassifier(),
        _dedupWindow = dedupWindow,
        _staleAfter = staleAfter,
        _now = now ?? DateTime.now;

  final LedgerRepository repository;
  final LedgerAppService ledger;
  final PaymentNotificationGateway notifications;
  final MerchantClassifier classifier;
  final Duration _dedupWindow;
  final Duration _staleAfter;
  final DateTime Function() _now;

  /// In-memory dedup cache for raw notification ids. The native queue already
  /// guards against duplicates, so this is purely a safety net.
  final Set<String> _seenRawIds = <String>{};

  /// Test hook to clear the in-memory dedup cache between tests.
  void resetForTest() {
    _seenRawIds.clear();
  }

  Future<AutoLedgerSyncReport> syncPending({
    String bookId = defaultBookId,
  }) async {
    final events = await notifications.getPendingEvents();
    if (events.isEmpty) {
      return const AutoLedgerSyncReport(posted: 0, duplicates: 0, skipped: 0);
    }

    await repository.seedIfEmpty();
    // Make sure default categories exist for this book before we start
    // classifying events; otherwise accountId() would resolve to a row
    // that is not in the database and createExpense would throw.
    await repository.listAccounts(bookId);

    final now = _now().toUtc();
    var posted = 0;
    var duplicates = 0;
    var skipped = 0;

    for (final event in events) {
      final occurredAt = event.occurredAt.toUtc();
      if (now.difference(occurredAt) > _staleAfter) {
        skipped += 1;
        _seenRawIds.add(event.id);
        continue;
      }
      if (_seenRawIds.contains(event.id)) {
        duplicates += 1;
        continue;
      }

      final isDuplicate = await _isDuplicateInLedger(event, bookId);
      _seenRawIds.add(event.id);
      if (isDuplicate) {
        duplicates += 1;
        continue;
      }

      try {
        await _postEvent(event, bookId: bookId);
        posted += 1;
      } catch (_) {
        // Leave the event id out of _seenRawIds so the next sync retries.
        _seenRawIds.remove(event.id);
      }
    }

    await notifications.clearPendingEvents();

    return AutoLedgerSyncReport(
      posted: posted,
      duplicates: duplicates,
      skipped: skipped,
    );
  }

  Future<void> _postEvent(
    PendingPaymentEvent event, {
    required String bookId,
  }) async {
    final amountMinor = BigInt.from(event.amountMinor);
    if (amountMinor <= BigInt.zero) {
      throw const FormatException('Amount must be positive');
    }

    final merchant = event.merchant?.trim();
    final categoryId = classifier.classify(
      merchant: merchant,
      direction: event.direction,
      bookId: bookId,
    );
    final description = describe(event, merchant);
    final fundingAccountId = accountKeyBank(bookId);
    final occurredAt = event.occurredAt.toUtc();

    if (event.direction == 'income') {
      await ledger.createIncome(
        incomeAccountId: categoryId,
        depositAccountId: fundingAccountId,
        amountMinor: amountMinor,
        description: description,
        occurredAt: occurredAt,
        source: autoLedgerSource,
      );
    } else {
      await ledger.createExpense(
        expenseAccountId: categoryId,
        fundingAccountId: fundingAccountId,
        amountMinor: amountMinor,
        description: description,
        occurredAt: occurredAt,
        source: autoLedgerSource,
      );
    }
  }

  /// Builds a user-facing description for a payment event.
  @visibleForTesting
  static String describe(PendingPaymentEvent event, String? merchant) {
    final platformLabel = switch (event.platform) {
      'wechat' => '微信支付',
      'alipay' => '支付宝',
      _ => event.platform,
    };
    final merchantPart =
        merchant == null || merchant.isEmpty ? '未知商户' : merchant;
    return '$platformLabel · $merchantPart';
  }

  Future<bool> _isDuplicateInLedger(
    PendingPaymentEvent event,
    String bookId,
  ) async {
    final start = event.occurredAt.subtract(_dedupWindow);
    final end = event.occurredAt.add(_dedupWindow);
    final window = await repository.watchSummariesSync(
      bookId,
      monthStart: start,
      monthEnd: end,
    );
    final needle = switch (event.platform) {
      'wechat' => '微信支付',
      'alipay' => '支付宝',
      _ => null,
    };
    final merchantLower = (event.merchant ?? '').toLowerCase();
    final expectedKind = event.direction == 'income'
        ? TransactionSummaryKind.income
        : TransactionSummaryKind.expense;
    final expectedMinor = BigInt.from(event.amountMinor);

    for (final tx in window) {
      if (tx.kind != expectedKind) continue;
      if (tx.amountMinor != expectedMinor) continue;
      if (needle != null && !(tx.description ?? '').contains(needle)) continue;
      if (merchantLower.isNotEmpty &&
          !(tx.description ?? '').toLowerCase().contains(merchantLower)) {
        continue;
      }
      final diff = tx.occurredAt.difference(event.occurredAt).abs();
      if (diff <= _dedupWindow) return true;
    }
    return false;
  }
}

/// Holds the singleton [AutoLedgerService] so the rest of the app can reach
/// it through Riverpod without instantiating dependencies by hand.
final autoLedgerServiceProvider = Provider<AutoLedgerService>((ref) {
  return AutoLedgerService(
    repository: ref.watch(ledgerRepositoryProvider),
    ledger: ref.watch(ledgerAppServiceProvider),
    notifications: PaymentNotificationService(),
  );
});

/// Triggers a one-shot sync against the currently-selected book.
///
/// Callers should listen to this provider and call `invalidateLedgerViews`
/// from a WidgetRef after the result lands, so the feed, accounts, and
/// reports screens reflect any newly-posted transactions.
final autoLedgerSyncProvider = FutureProvider<AutoLedgerSyncReport>((ref) async {
  final service = ref.watch(autoLedgerServiceProvider);
  final bookId = ref.watch(selectedBookIdProvider);
  return service.syncPending(bookId: bookId);
});
