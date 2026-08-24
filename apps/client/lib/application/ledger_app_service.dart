import 'package:ledger_domain/ledger_domain.dart' as domain;

import '../data/database.dart';
import '../data/ledger_repository.dart';
import '../domain/default_categories.dart';
import '../domain/ids.dart';
import '../l10n/l10n.dart';

class LedgerAppService {
  LedgerAppService(this._repo, {String bookId = defaultBookId})
      : bookId = domain.BookId(bookId);

  final LedgerRepository _repo;
  static const factory = domain.TransactionFactory();
  final domain.BookId bookId;

  Future<void> createExpense({
    required String expenseAccountId,
    required String fundingAccountId,
    required BigInt amountMinor,
    String? description,
    DateTime? occurredAt,
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
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
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
    DateTime? occurredAt,
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
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
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
    DateTime? occurredAt,
  }) async {
    final accounts = await _repo.listAccounts(bookId.value);
    final from = _asDomain(accounts.firstWhere((a) => a.id == fromAccountId));
    final to = _asDomain(accounts.firstWhere((a) => a.id == toAccountId));
    final mutationId = _repo.newId();
    final tx = factory.transfer(
      id: domain.TransactionId(_repo.newId()),
      bookId: bookId,
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
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

  Future<void> updateExpense({
    required String transactionId,
    required DateTime occurredAt,
    required int version,
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
    final tx = factory.expense(
      id: domain.TransactionId(transactionId),
      bookId: bookId,
      occurredAt: occurredAt.toUtc(),
      expenseAccount: expense,
      fundingAccount: funding,
      amount: domain.Money(
        minorUnits: amountMinor,
        currency: domain.CurrencyCode.cny,
      ),
      description: description,
    );
    await _repo.updateDomainTransaction(
      tx,
      baseVersion: version,
      mutationId: _repo.newId(),
    );
  }

  Future<void> updateIncome({
    required String transactionId,
    required DateTime occurredAt,
    required int version,
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
    final tx = factory.income(
      id: domain.TransactionId(transactionId),
      bookId: bookId,
      occurredAt: occurredAt.toUtc(),
      incomeAccount: income,
      depositAccount: deposit,
      amount: domain.Money(
        minorUnits: amountMinor,
        currency: domain.CurrencyCode.cny,
      ),
      description: description,
    );
    await _repo.updateDomainTransaction(
      tx,
      baseVersion: version,
      mutationId: _repo.newId(),
    );
  }

  Future<void> updateTransfer({
    required String transactionId,
    required DateTime occurredAt,
    required int version,
    required String fromAccountId,
    required String toAccountId,
    required BigInt amountMinor,
    String? description,
  }) async {
    final accounts = await _repo.listAccounts(bookId.value);
    final from = _asDomain(accounts.firstWhere((a) => a.id == fromAccountId));
    final to = _asDomain(accounts.firstWhere((a) => a.id == toAccountId));
    final tx = factory.transfer(
      id: domain.TransactionId(transactionId),
      bookId: bookId,
      occurredAt: occurredAt.toUtc(),
      from: from,
      to: to,
      amount: domain.Money(
        minorUnits: amountMinor,
        currency: domain.CurrencyCode.cny,
      ),
      description: description,
    );
    await _repo.updateDomainTransaction(
      tx,
      baseVersion: version,
      mutationId: _repo.newId(),
    );
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
    String? parentCategoryId,
  }) async {
    _validateCategoryType(type);
    final normalizedName = _normalizeCategoryName(name);
    final accounts = await _repo.listAccounts(bookId.value);
    _validateCategoryParent(
      parentCategoryId: parentCategoryId,
      categoryType: type,
      accounts: accounts,
    );
    await _ensureUniqueCategoryName(
      name: normalizedName,
      type: type,
      accounts: accounts,
    );
    final id = accountId(bookId.value, _repo.newId());
    await _repo.createLocalAccount(
      id: id,
      bookId: bookId.value,
      name: normalizedName,
      type: type,
      parentAccountId: parentCategoryId,
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
      throw CategoryValidationException(L10n.current.categoryNotFound);
    }

    await updateCategory(
      categoryId: category.id,
      name: name,
      parentCategoryId: category.parentAccountId,
    );
  }

  Future<void> updateCategory({
    required String categoryId,
    required String name,
    required String? parentCategoryId,
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
      throw CategoryValidationException(L10n.current.categoryNotFound);
    }

    _validateCategoryParent(
      parentCategoryId: parentCategoryId,
      categoryType: category.type,
      categoryId: category.id,
      accounts: accounts,
    );
    if (parentCategoryId != null &&
        accounts.any((account) => account.parentAccountId == category!.id)) {
      throw CategoryValidationException(
          L10n.current.cannotNestRootWithChildren);
    }

    final normalizedName = _normalizeCategoryName(name);
    await _ensureUniqueCategoryName(
      name: normalizedName,
      type: category.type,
      excludingId: category.id,
      accounts: accounts,
    );
    await _repo.updateLocalCategory(
      id: category.id,
      name: normalizedName,
      parentAccountId: parentCategoryId,
    );
  }

  String _normalizeCategoryName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw CategoryValidationException(L10n.current.enterCategoryName);
    }
    if (normalized.length > 24) {
      throw CategoryValidationException(L10n.current.categoryNameTooLong);
    }
    return normalized;
  }

  void _validateCategoryType(String type) {
    if (type != 'expense' && type != 'income') {
      throw CategoryValidationException(L10n.current.invalidCategoryType);
    }
  }

  void _validateCategoryParent({
    required String? parentCategoryId,
    required String categoryType,
    required List<Account> accounts,
    String? categoryId,
  }) {
    if (parentCategoryId == null) return;
    if (parentCategoryId == categoryId) {
      throw CategoryValidationException(L10n.current.categoryCannotBeOwnParent);
    }

    Account? parent;
    for (final account in accounts) {
      if (account.id == parentCategoryId) {
        parent = account;
        break;
      }
    }
    if (parent == null ||
        parent.type != categoryType ||
        (parent.type != 'expense' && parent.type != 'income')) {
      throw CategoryValidationException(L10n.current.chooseSameTypeParent);
    }
    if (parent.parentAccountId != null) {
      throw CategoryValidationException(L10n.current.categoryMaxTwoLevels);
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
      throw CategoryValidationException(L10n.current.duplicateCategoryName);
    }
  }

  String _categoryComparisonKey(String name) {
    return defaultCategoryComparisonKey(name);
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
