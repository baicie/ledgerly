import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ledger_repository.dart';
import 'design/ledgerly_theme.dart';
import 'providers.dart';
import 'widgets/ledgerly_finance.dart';
import 'widgets/quick_entry_fields.dart';
import 'widgets/quick_entry_keypad.dart';

enum QuickEntryMode { expense, income, transfer }

class QuickEntrySheet extends ConsumerStatefulWidget {
  const QuickEntrySheet({super.key});

  @override
  ConsumerState<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends ConsumerState<QuickEntrySheet> {
  final _note = TextEditingController();
  var _mode = QuickEntryMode.expense;
  var _amount = '0';
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  var _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(accountBalancesProvider);
    return Material(
      color: LedgerlyColors.surface,
      child: SafeArea(
        top: false,
        child: balances.when(
          data: _buildForm,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('账户加载失败：$error')),
        ),
      ),
    );
  }

  Widget _buildForm(List<AccountBalanceRow> rows) {
    final categories = rows
        .where((row) =>
            row.type == (_mode == QuickEntryMode.income ? 'income' : 'expense'))
        .toList();
    final accounts = rows
        .where((row) => row.type == 'asset' || row.type == 'liability')
        .toList();
    final category = _findRow(categories, _categoryId);
    final account = _findRow(accounts, _accountId);
    final toAccount = _findRow(
      accounts,
      _toAccountId,
      fallbackIndex: accounts.length > 1 ? 1 : 0,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '记一笔',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<QuickEntryMode>(
              segments: const [
                ButtonSegment(value: QuickEntryMode.expense, label: Text('支出')),
                ButtonSegment(value: QuickEntryMode.income, label: Text('收入')),
                ButtonSegment(
                    value: QuickEntryMode.transfer, label: Text('转账')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.single;
                  _categoryId = null;
                });
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _modeLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _displayAmount,
                  style: TextStyle(
                    color: _modeColor,
                    fontSize: 48,
                    height: 1.05,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: _modeColor, thickness: 2),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Material(
              color: LedgerlyColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: LedgerlyColors.divider),
              ),
              child: Column(
                children: [
                  if (_mode != QuickEntryMode.transfer)
                    QuickEntrySelectionField(
                      key: const Key('quick-category-field'),
                      label: '分类',
                      value: localizedLedgerName(category?.name),
                      icon: ledgerIconFor(category?.name),
                      color: ledgerColorFor(
                        category?.name,
                        kind: _mode == QuickEntryMode.income
                            ? TransactionSummaryKind.income
                            : TransactionSummaryKind.expense,
                      ),
                      onTap: () => _pickCategory(categories, category?.id),
                    ),
                  QuickEntrySelectionField(
                    label: _mode == QuickEntryMode.transfer ? '转出账户' : '账户',
                    value: localizedLedgerName(account?.name),
                    icon: ledgerIconFor(account?.name),
                    color: ledgerColorFor(account?.name),
                    onTap: accounts.isEmpty
                        ? null
                        : () => _pickAccount(accounts, account?.id),
                  ),
                  if (_mode == QuickEntryMode.transfer)
                    QuickEntrySelectionField(
                      label: '转入账户',
                      value: localizedLedgerName(toAccount?.name),
                      icon: ledgerIconFor(toAccount?.name),
                      color: ledgerColorFor(toAccount?.name),
                      onTap: accounts.isEmpty
                          ? null
                          : () => _pickToAccount(accounts, toAccount?.id),
                    ),
                  const Divider(indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _note,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: '备注（可选）',
                        prefixIcon: Icon(Icons.bookmark_border),
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        QuickEntryKeypad(onDigit: _enter, onBackspace: _backspace),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('quick-entry-save'),
              onPressed: _busy
                  ? null
                  : () => _submit(
                        category: category,
                        account: account,
                        toAccount: toAccount,
                      ),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_busy ? '保存中' : _saveLabel),
            ),
          ),
        ),
      ],
    );
  }

  String get _modeLabel => switch (_mode) {
        QuickEntryMode.expense => '支出金额',
        QuickEntryMode.income => '收入金额',
        QuickEntryMode.transfer => '转账金额',
      };

  String get _saveLabel => switch (_mode) {
        QuickEntryMode.expense => '保存支出',
        QuickEntryMode.income => '保存收入',
        QuickEntryMode.transfer => '保存转账',
      };

  Color get _modeColor => switch (_mode) {
        QuickEntryMode.expense => LedgerlyColors.expense,
        QuickEntryMode.income => LedgerlyColors.income,
        QuickEntryMode.transfer => LedgerlyColors.chartBlue,
      };

  BigInt get _amountMinor {
    final parts = _amount.split('.');
    final yuan = BigInt.tryParse(parts.first) ?? BigInt.zero;
    final centsText =
        parts.length == 1 ? '00' : parts[1].padRight(2, '0').substring(0, 2);
    return yuan * BigInt.from(100) + BigInt.from(int.parse(centsText));
  }

  String get _displayAmount => formatDisplayMinor(_amountMinor, symbol: false);

  void _enter(String value) {
    setState(() {
      if (value == '.') {
        if (!_amount.contains('.')) _amount = '$_amount.';
        return;
      }
      final decimal = _amount.indexOf('.');
      if (decimal >= 0 && _amount.length - decimal > 2) return;
      if (decimal < 0 && _amount.length >= 9) return;
      _amount = _amount == '0' ? value : '$_amount$value';
    });
  }

  void _backspace() {
    setState(() {
      _amount =
          _amount.length <= 1 ? '0' : _amount.substring(0, _amount.length - 1);
    });
  }

  AccountBalanceRow? _findRow(
    List<AccountBalanceRow> rows,
    String? id, {
    int fallbackIndex = 0,
  }) {
    for (final row in rows) {
      if (row.id == id) return row;
    }
    if (rows.isEmpty) return null;
    final index = fallbackIndex < 0
        ? 0
        : fallbackIndex >= rows.length
            ? rows.length - 1
            : fallbackIndex;
    return rows[index];
  }

  Future<void> _pickCategory(
    List<AccountBalanceRow> rows,
    String? selectedId,
  ) async {
    final id = await showQuickEntryPicker(
      context: context,
      title: _mode == QuickEntryMode.income ? '选择收入分类' : '选择支出分类',
      rows: rows,
      selectedId: selectedId,
      categoryType: _mode == QuickEntryMode.income ? 'income' : 'expense',
    );
    if (id != null && mounted) setState(() => _categoryId = id);
  }

  Future<void> _pickAccount(
    List<AccountBalanceRow> rows,
    String? selectedId,
  ) async {
    final id = await showQuickEntryPicker(
      context: context,
      title: _mode == QuickEntryMode.transfer ? '选择转出账户' : '选择账户',
      rows: rows,
      selectedId: selectedId,
    );
    if (id != null && mounted) setState(() => _accountId = id);
  }

  Future<void> _pickToAccount(
    List<AccountBalanceRow> rows,
    String? selectedId,
  ) async {
    final id = await showQuickEntryPicker(
      context: context,
      title: '选择转入账户',
      rows: rows,
      selectedId: selectedId,
    );
    if (id != null && mounted) setState(() => _toAccountId = id);
  }

  Future<void> _submit({
    required AccountBalanceRow? category,
    required AccountBalanceRow? account,
    required AccountBalanceRow? toAccount,
  }) async {
    if (_amountMinor <= BigInt.zero) {
      _showMessage('请输入大于 0 的金额');
      return;
    }
    if (account == null ||
        (_mode != QuickEntryMode.transfer && category == null)) {
      _showMessage('当前账本缺少可用的分类或账户');
      return;
    }
    if (_mode == QuickEntryMode.transfer &&
        (toAccount == null || toAccount.id == account.id)) {
      _showMessage('转出账户和转入账户不能相同');
      return;
    }

    setState(() => _busy = true);
    final description = _note.text.trim().isEmpty ? null : _note.text.trim();
    try {
      final service = ref.read(ledgerAppServiceProvider);
      switch (_mode) {
        case QuickEntryMode.expense:
          await service.createExpense(
            expenseAccountId: category!.id,
            fundingAccountId: account.id,
            amountMinor: _amountMinor,
            description: description,
          );
        case QuickEntryMode.income:
          await service.createIncome(
            incomeAccountId: category!.id,
            depositAccountId: account.id,
            amountMinor: _amountMinor,
            description: description,
          );
        case QuickEntryMode.transfer:
          await service.createTransfer(
            fromAccountId: account.id,
            toAccountId: toAccount!.id,
            amountMinor: _amountMinor,
            description: description,
          );
      }
      ref.invalidate(monthTransactionsProvider);
      ref.invalidate(monthlyLedgerSummaryProvider);
      ref.invalidate(categoryReportProvider);
      ref.invalidate(transactionListProvider);
      ref.invalidate(accountBalancesProvider);
      if (mounted) Navigator.maybePop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _showMessage('保存失败：$error');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
