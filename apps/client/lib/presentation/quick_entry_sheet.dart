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
  const QuickEntrySheet({super.key, this.transaction});

  final TransactionSummary? transaction;

  @override
  ConsumerState<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends ConsumerState<QuickEntrySheet> {
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  var _mode = QuickEntryMode.expense;
  var _amount = '0';
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(_handleNoteFocus);
    final transaction = widget.transaction;
    if (transaction != null) {
      _mode = switch (transaction.kind) {
        TransactionSummaryKind.income => QuickEntryMode.income,
        TransactionSummaryKind.transfer => QuickEntryMode.transfer,
        _ => QuickEntryMode.expense,
      };
      _amount = _amountInput(transaction.amountMinor);
      _categoryId = transaction.categoryAccountId;
      _accountId = transaction.accountId;
      _toAccountId = transaction.toAccountId;
      _note.text = transaction.description ?? '';
    }
  }

  @override
  void dispose() {
    _noteFocus
      ..removeListener(_handleNoteFocus)
      ..dispose();
    _note.dispose();
    super.dispose();
  }

  void _handleNoteFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(accountBalancesProvider);
    final shortViewport = MediaQuery.sizeOf(context).height < 600;
    return Material(
      color: LedgerlyColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: balances.when(
          data: (rows) => _buildForm(rows, shortViewport: shortViewport),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('账户加载失败：$error')),
        ),
      ),
    );
  }

  Widget _buildForm(
    List<AccountBalanceRow> rows, {
    required bool shortViewport,
  }) {
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
          padding: shortViewport
              ? const EdgeInsets.fromLTRB(12, 0, 4, 0)
              : const EdgeInsets.fromLTRB(16, 6, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.transaction == null ? '记一笔' : '编辑流水',
                  style: shortViewport
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                visualDensity: shortViewport
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                constraints: shortViewport
                    ? const BoxConstraints.tightFor(width: 40, height: 40)
                    : null,
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              12, shortViewport ? 0 : 4, 12, shortViewport ? 0 : 4),
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
                _noteFocus.unfocus();
                setState(() {
                  _mode = selection.single;
                  _categoryId = null;
                });
              },
            ),
          ),
        ),
        Padding(
          padding: shortViewport
              ? const EdgeInsets.fromLTRB(16, 1, 16, 1)
              : const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!shortViewport) ...[
                Text(
                  _modeLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 1),
              ],
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  _displayAmount,
                  style: TextStyle(
                    color: _modeColor,
                    fontSize: shortViewport ? 32 : 40,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(height: shortViewport ? 1 : 4),
              SizedBox(
                width: 44,
                child: Divider(color: _modeColor, thickness: 2),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
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
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: TextField(
                      key: const Key('quick-entry-note'),
                      controller: _note,
                      focusNode: _noteFocus,
                      maxLength: 120,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _noteFocus.unfocus(),
                      decoration: const InputDecoration(
                        hintText: '添加备注（可选）',
                        prefixIcon: Icon(Icons.edit_note_outlined, size: 20),
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!_noteFocus.hasFocus)
          QuickEntryKeypad(
            compact: shortViewport,
            onDigit: _enter,
            onBackspace: _backspace,
          ),
        Padding(
          padding: shortViewport
              ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
              : const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
        QuickEntryMode.expense => _isEditing ? '更新支出' : '保存支出',
        QuickEntryMode.income => _isEditing ? '更新收入' : '保存收入',
        QuickEntryMode.transfer => _isEditing ? '更新转账' : '保存转账',
      };

  bool get _isEditing => widget.transaction != null;

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

  String _amountInput(BigInt minor) {
    final absolute = minor.abs();
    final yuan = absolute ~/ BigInt.from(100);
    final cents = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
    return '$yuan.$cents';
  }

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
      final transaction = widget.transaction;
      if (transaction == null) {
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
      } else {
        switch (_mode) {
          case QuickEntryMode.expense:
            await service.updateExpense(
              transactionId: transaction.id,
              occurredAt: transaction.occurredAt,
              version: transaction.version,
              expenseAccountId: category!.id,
              fundingAccountId: account.id,
              amountMinor: _amountMinor,
              description: description,
            );
          case QuickEntryMode.income:
            await service.updateIncome(
              transactionId: transaction.id,
              occurredAt: transaction.occurredAt,
              version: transaction.version,
              incomeAccountId: category!.id,
              depositAccountId: account.id,
              amountMinor: _amountMinor,
              description: description,
            );
          case QuickEntryMode.transfer:
            await service.updateTransfer(
              transactionId: transaction.id,
              occurredAt: transaction.occurredAt,
              version: transaction.version,
              fromAccountId: account.id,
              toAccountId: toAccount!.id,
              amountMinor: _amountMinor,
              description: description,
            );
        }
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
