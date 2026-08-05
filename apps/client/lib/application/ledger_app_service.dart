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
    return _repo.createLocalAccount(
      id: accountId(bookId.value, _repo.newId()),
      bookId: bookId.value,
      name: name,
      type: type,
    );
  }

  Future<String> createCategory({
    required String name,
    required String type,
  }) async {
    _validateCategoryType(type);
    final normalizedName = _normalizeCategoryName(name);
    await _ensureUniqueCategoryName(
      name: normalizedName,
      type: type,
    );
    final id = accountId(bookId.value, _repo.newId());
    await _repo.createLocalAccount(
      id: id,
      bookId: bookId.value,
      name: normalizedName,
      type: type,
    );
    return id;
  }

  Future<void> renameCategory({
    required String categoryId,
    required String name,
  }) async {
    final accounts = await _repo.listAccounts(bookId.value);
    Account? category;
    for (final account in accounts) {
      if (account.id == categoryId) {
        category = account;
        break;
      }
    }
    if (category == null ||
        (category.type != 'expense' && category.type != 'income')) {
      throw const CategoryValidationException('分类不存在');
    }

    final normalizedName = _normalizeCategoryName(name);
    await _ensureUniqueCategoryName(
      name: normalizedName,
      type: category.type,
      excludingId: category.id,
      accounts: accounts,
    );
    await _repo.renameLocalAccount(id: category.id, name: normalizedName);
  }

  String _normalizeCategoryName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const CategoryValidationException('请输入分类名称');
    }
    if (normalized.length > 24) {
      throw const CategoryValidationException('分类名称不能超过 24 个字符');
    }
    return normalized;
  }

  void _validateCategoryType(String type) {
    if (type != 'expense' && type != 'income') {
      throw const CategoryValidationException('分类类型无效');
    }
  }

  Future<void> _ensureUniqueCategoryName({
    required String name,
    required String type,
    String? excludingId,
    List<Account>? accounts,
  }) async {
    final existing = accounts ?? await _repo.listAccounts(bookId.value);
    final normalizedName = _categoryComparisonKey(name);
    final duplicate = existing.any(
      (account) =>
          account.type == type &&
          account.id != excludingId &&
          _categoryComparisonKey(account.name) == normalizedName,
    );
    if (duplicate) {
      throw const CategoryValidationException('同类型下已存在该分类');
    }
  }

  String _categoryComparisonKey(String name) {
    return switch (name.trim().toLowerCase()) {
      'food' || '餐饮' => 'built-in:food',
      'transport' || '交通' => 'built-in:transport',
      'salary' || '工资收入' => 'built-in:salary',
      final value => value,
    };
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

class CategoryValidationException implements Exception {
  const CategoryValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
