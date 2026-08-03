import 'account.dart';
import 'entry.dart';
import 'errors.dart';
import 'ids.dart';
import 'money.dart';
import 'transaction.dart';

/// Builds balanced transactions from domain intents.
final class TransactionFactory {
  const TransactionFactory();

  /// Expense: debit expense (+), credit asset/liability (-).
  LedgerTransaction expense({
    required TransactionId id,
    required BookId bookId,
    required DateTime occurredAt,
    required Account expenseAccount,
    required Account fundingAccount,
    required Money amount,
    String? description,
    EntryId? expenseEntryId,
    EntryId? fundingEntryId,
  }) {
    _requireType(expenseAccount, AccountType.expense);
    _requireCurrency(expenseAccount, amount);
    _requireCurrency(fundingAccount, amount);
    return LedgerTransaction(
      id: id,
      bookId: bookId,
      occurredAt: occurredAt,
      description: description,
      entries: [
        TransactionEntry(
          id: expenseEntryId ?? EntryId('${id.value}-0'),
          transactionId: id,
          accountId: expenseAccount.id,
          amount: amount,
          index: 0,
        ),
        TransactionEntry(
          id: fundingEntryId ?? EntryId('${id.value}-1'),
          transactionId: id,
          accountId: fundingAccount.id,
          amount: -amount,
          index: 1,
        ),
      ],
    );
  }

  /// Income: debit asset (+), credit income (- convention as credit).
  LedgerTransaction income({
    required TransactionId id,
    required BookId bookId,
    required DateTime occurredAt,
    required Account incomeAccount,
    required Account depositAccount,
    required Money amount,
    String? description,
  }) {
    _requireType(incomeAccount, AccountType.income);
    _requireCurrency(incomeAccount, amount);
    _requireCurrency(depositAccount, amount);
    return LedgerTransaction(
      id: id,
      bookId: bookId,
      occurredAt: occurredAt,
      description: description,
      entries: [
        TransactionEntry(
          id: EntryId('${id.value}-0'),
          transactionId: id,
          accountId: depositAccount.id,
          amount: amount,
          index: 0,
        ),
        TransactionEntry(
          id: EntryId('${id.value}-1'),
          transactionId: id,
          accountId: incomeAccount.id,
          amount: -amount,
          index: 1,
        ),
      ],
    );
  }

  /// Transfer between two asset/liability accounts.
  LedgerTransaction transfer({
    required TransactionId id,
    required BookId bookId,
    required DateTime occurredAt,
    required Account from,
    required Account to,
    required Money amount,
    String? description,
  }) {
    if (from.id == to.id) {
      throw const DomainException(
        DomainErrorCode.invalidTransfer,
        'Transfer accounts must differ',
      );
    }
    _requireCurrency(from, amount);
    _requireCurrency(to, amount);
    return LedgerTransaction(
      id: id,
      bookId: bookId,
      occurredAt: occurredAt,
      description: description,
      entries: [
        TransactionEntry(
          id: EntryId('${id.value}-0'),
          transactionId: id,
          accountId: from.id,
          amount: -amount,
          index: 0,
        ),
        TransactionEntry(
          id: EntryId('${id.value}-1'),
          transactionId: id,
          accountId: to.id,
          amount: amount,
          index: 1,
        ),
      ],
    );
  }

  /// Split expense across multiple expense lines funded by one account.
  LedgerTransaction splitExpense({
    required TransactionId id,
    required BookId bookId,
    required DateTime occurredAt,
    required Account fundingAccount,
    required List<({Account account, Money amount})> splits,
    String? description,
  }) {
    if (splits.length < 2) {
      throw const DomainException(
        DomainErrorCode.tooFewEntries,
        'Split requires at least two expense lines',
      );
    }
    final total = splits.fold<BigInt>(
      BigInt.zero,
      (acc, s) => acc + s.amount.minorUnits,
    );
    final currency = splits.first.amount.currency;
    final entries = <TransactionEntry>[];
    var index = 0;
    for (final split in splits) {
      _requireType(split.account, AccountType.expense);
      if (split.amount.currency != currency) {
        throw const DomainException(
          DomainErrorCode.currencyMismatch,
          'Split currencies must match',
        );
      }
      entries.add(
        TransactionEntry(
          id: EntryId('${id.value}-$index'),
          transactionId: id,
          accountId: split.account.id,
          amount: split.amount,
          index: index,
        ),
      );
      index++;
    }
    final funding = Money(minorUnits: total, currency: currency);
    _requireCurrency(fundingAccount, funding);
    entries.add(
      TransactionEntry(
        id: EntryId('${id.value}-$index'),
        transactionId: id,
        accountId: fundingAccount.id,
        amount: -funding,
        index: index,
      ),
    );
    return LedgerTransaction(
      id: id,
      bookId: bookId,
      occurredAt: occurredAt,
      description: description,
      entries: entries,
    );
  }

  /// Refund: reverse an expense (asset +, expense -).
  LedgerTransaction refundExpense({
    required TransactionId id,
    required BookId bookId,
    required DateTime occurredAt,
    required Account expenseAccount,
    required Account refundToAccount,
    required Money amount,
    String? description,
  }) {
    _requireType(expenseAccount, AccountType.expense);
    _requireCurrency(expenseAccount, amount);
    _requireCurrency(refundToAccount, amount);
    return LedgerTransaction(
      id: id,
      bookId: bookId,
      occurredAt: occurredAt,
      description: description,
      entries: [
        TransactionEntry(
          id: EntryId('${id.value}-0'),
          transactionId: id,
          accountId: refundToAccount.id,
          amount: amount,
          index: 0,
        ),
        TransactionEntry(
          id: EntryId('${id.value}-1'),
          transactionId: id,
          accountId: expenseAccount.id,
          amount: -amount,
          index: 1,
        ),
      ],
    );
  }

  void _requireType(Account account, AccountType type) {
    if (account.type != type) {
      throw DomainException(
        DomainErrorCode.invalidAccount,
        'Expected $type account, got ${account.type}',
      );
    }
  }

  void _requireCurrency(Account account, Money amount) {
    if (account.currency != amount.currency) {
      throw DomainException(
        DomainErrorCode.currencyMismatch,
        'Account ${account.id} currency ${account.currency} != ${amount.currency}',
      );
    }
  }
}
