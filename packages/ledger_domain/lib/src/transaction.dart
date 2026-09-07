import 'entry.dart';
import 'errors.dart';
import 'ids.dart';

final class LedgerTransaction {
  LedgerTransaction({
    required this.id,
    required this.bookId,
    required this.occurredAt,
    required List<TransactionEntry> entries,
    this.description,
    this.version = 1,
    this.source,
  }) : entries = List.unmodifiable(entries) {
    if (entries.length < 2) {
      throw const DomainException(
        DomainErrorCode.tooFewEntries,
        'Transaction requires at least two entries',
      );
    }
    for (final e in entries) {
      if (e.transactionId != id) {
        throw const DomainException(
          DomainErrorCode.invalidTransfer,
          'Entry transactionId mismatch',
        );
      }
    }
    validateBalanced();
  }

  final TransactionId id;
  final BookId bookId;
  final DateTime occurredAt;
  final String? description;
  final int version;
  final List<TransactionEntry> entries;

  /// Provenance tag for how this transaction entered the ledger.
  ///
  /// Reserved values:
  /// - `auto_ledger`: created by AutoLedgerService from a captured payment
  ///   notification (Android `NotificationListenerService`).
  /// - `manual` (default): entered directly by the user through the UI.
  ///
  /// The field is opaque to the domain layer; consumers may pass arbitrary
  /// short strings and are responsible for keeping them stable.
  final String? source;

  void validateBalanced() {
    final currencies = entries.map((e) => e.amount.currency).toSet();
    if (currencies.length != 1) {
      throw const DomainException(
        DomainErrorCode.currencyMismatch,
        'All entries must share one currency in Phase 0',
      );
    }
    final sum = entries.fold<BigInt>(
      BigInt.zero,
      (acc, e) => acc + e.amount.minorUnits,
    );
    if (sum != BigInt.zero) {
      throw DomainException(
        DomainErrorCode.unbalanced,
        'Entries sum to $sum, expected 0',
      );
    }
  }

  /// Projection helper: sum of signed amounts for an account.
  BigInt balanceContribution(AccountId accountId) {
    return entries
        .where((e) => e.accountId == accountId)
        .fold<BigInt>(BigInt.zero, (acc, e) => acc + e.amount.minorUnits);
  }
}
