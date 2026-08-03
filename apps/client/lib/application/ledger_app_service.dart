import 'package:ledger_domain/ledger_domain.dart' as domain;

import '../data/database.dart';
import '../data/ledger_repository.dart';
import '../domain/ids.dart';

class LedgerAppService {
  LedgerAppService(this._repo);

  final LedgerRepository _repo;
  static const factory = domain.TransactionFactory();
  static const bookId = domain.BookId(defaultBookId);

  Future<void> createExpense({
    required String expenseAccountId,
    required String fundingAccountId,
    required BigInt amountMinor,
    String? description,
  }) async {
    final accounts = await _repo.listAccounts(bookId.value);
    final expense =
        _asDomain(accounts.firstWhere((a) => a.id == expenseAccountId));
    final funding =
        _asDomain(accounts.firstWhere((a) => a.id == fundingAccountId));
    final mutationId = _repo.newId();
    final tx = factory.expense(
      id: domain.TransactionId(_repo.newId()),
      bookId: bookId,
      occurredAt: DateTime.now().toUtc(),
      expenseAccount: expense,
      fundingAccount: funding,
      amount: domain.Money(
        minorUnits: amountMinor,
        currency: domain.CurrencyCode.cny,
      ),
      description: description,
    );
    await _repo.saveDomainTransaction(tx, mutationId: mutationId);
  }

  Future<void> createIncome({
    required String incomeAccountId,
    required String depositAccountId,
    required BigInt amountMinor,
    String? description,
  }) async {
    final accounts = await _repo.listAccounts(bookId.value);
    final income =
        _asDomain(accounts.firstWhere((a) => a.id == incomeAccountId));
    final deposit =
        _asDomain(accounts.firstWhere((a) => a.id == depositAccountId));
    final mutationId = _repo.newId();
    final tx = factory.income(
      id: domain.TransactionId(_repo.newId()),
      bookId: bookId,
      occurredAt: DateTime.now().toUtc(),
      incomeAccount: income,
      depositAccount: deposit,
      amount: domain.Money(
        minorUnits: amountMinor,
        currency: domain.CurrencyCode.cny,
      ),
      description: description,
    );
    await _repo.saveDomainTransaction(tx, mutationId: mutationId);
  }

  Future<void> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required BigInt amountMinor,
    String? description,
  }) async {
    final accounts = await _repo.listAccounts(bookId.value);
    final from = _asDomain(accounts.firstWhere((a) => a.id == fromAccountId));
    final to = _asDomain(accounts.firstWhere((a) => a.id == toAccountId));
    final mutationId = _repo.newId();
    final tx = factory.transfer(
      id: domain.TransactionId(_repo.newId()),
      bookId: bookId,
      occurredAt: DateTime.now().toUtc(),
      from: from,
      to: to,
      amount: domain.Money(
        minorUnits: amountMinor,
        currency: domain.CurrencyCode.cny,
      ),
      description: description,
    );
    await _repo.saveDomainTransaction(tx, mutationId: mutationId);
  }

  Future<void> deleteTransaction(String txId) {
    return _repo.softDeleteTransaction(txId, bookId.value);
  }

  Future<void> createAccount({
    required String name,
    required String type,
  }) {
    return _repo.upsertAccount(
      id: accountId(bookId.value, _repo.newId()),
      bookId: bookId.value,
      name: name,
      type: type,
    );
  }

  domain.Account _asDomain(Account row) {
    return domain.Account(
      id: domain.AccountId(row.id),
      bookId: domain.BookId(row.bookId),
      name: row.name,
      type: domain.AccountType.values.firstWhere((t) => t.name == row.type),
      currency: domain.CurrencyCode.parse(row.currencyCode),
    );
  }
}
