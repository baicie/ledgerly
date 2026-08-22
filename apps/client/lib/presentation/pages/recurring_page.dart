import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/amount_parse.dart';
import '../../data/local_recurring_repository.dart';
import '../../domain/ids.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';

class RecurringPage extends ConsumerStatefulWidget {
  const RecurringPage({super.key});

  @override
  ConsumerState<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends ConsumerState<RecurringPage> {
  late final TextEditingController _name;
  final _amount = TextEditingController();
  var _kind = 'expense';
  var _dayOfMonth = DateTime.now().day.clamp(1, 31);
  String? _categoryId;
  String? _accountId;
  var _busy = false;
  String? _message;
  List<LocalRecurringRule> _rules = const [];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: L10n.current.monthlyRent);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final rules =
          await ref.read(localRecurringRepositoryProvider).list(defaultBookId);
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final l10n = l10nOf(context);
    final amount = parsePositiveAmountMinor(_amount.text);
    if (amount == null || _categoryId == null || _accountId == null) {
      setState(() => _message = l10n.enterPositiveDecimalAmount);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(localRecurringRepositoryProvider).insert(
            bookId: defaultBookId,
            name: _name.text.trim().isEmpty ? l10n.monthlyRent : _name.text.trim(),
            kind: _kind,
            amountMinor: amount,
            categoryAccountId: _categoryId!,
            accountId: _accountId!,
            dayOfMonth: _dayOfMonth,
          );
      await ref.read(recurringSchedulerProvider).catchUp();
      invalidateLedgerViews(ref);
      _amount.clear();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final categories = ref.watch(categoryAccountsProvider(_kind)).valueOrNull ??
        const <CategoryAccountRow>[];
    final accounts = (ref.watch(accountBalancesProvider).valueOrNull ??
            const <AccountBalanceRow>[])
        .where((row) => row.type == 'asset')
        .toList();
    _categoryId ??= categories.isEmpty ? null : categories.first.id;
    _accountId ??= accounts.isEmpty
        ? accountKeyCash(defaultBookId)
        : accounts.first.id;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recurring)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LedgerlySection(child: Text(l10n.recurringLocalHelp)),
            const SizedBox(height: 12),
            LedgerlySection(
              title: l10n.createRule,
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: l10n.ruleName),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: InputDecoration(labelText: l10n.kindLabel),
                    items: [
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text(l10n.kindExpense),
                      ),
                      DropdownMenuItem(
                        value: 'income',
                        child: Text(l10n.kindIncome),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _kind = value;
                        _categoryId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (categories.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: categories.any((c) => c.id == _categoryId)
                          ? _categoryId
                          : categories.first.id,
                      decoration:
                          InputDecoration(labelText: l10n.expenseCategory),
                      items: [
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(
                              localizedLedgerName(l10n, category.name),
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
                  const SizedBox(height: 12),
                  if (accounts.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: accounts.any((a) => a.id == _accountId)
                          ? _accountId
                          : accounts.first.id,
                      decoration: InputDecoration(labelText: l10n.fundingAccount),
                      items: [
                        for (final account in accounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(
                              localizedLedgerName(l10n, account.name),
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _accountId = value),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.amountYuan,
                      prefixText: '¥ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _dayOfMonth,
                    decoration: InputDecoration(
                      labelText: l10n.dayOfMonth,
                      helperText: l10n.lastDayOfMonthHint,
                    ),
                    items: [
                      for (var day = 1; day <= 31; day++)
                        DropdownMenuItem(value: day, child: Text('$day')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _dayOfMonth = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Text(_busy ? l10n.processing : l10n.createRule),
                  ),
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
            const SizedBox(height: 16),
            for (final rule in _rules)
              Card(
                child: ListTile(
                  title: Text(rule.name),
                  subtitle: Text(
                    '${rule.kind == 'income' ? l10n.kindIncome : l10n.kindExpense} · ${formatDisplayMinor(rule.amountMinor)}\n${l10n.nextRunDate(rule.nextRunDate)}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: rule.active ? l10n.pauseRule : l10n.resumeRule,
                        onPressed: () async {
                          await ref
                              .read(localRecurringRepositoryProvider)
                              .setActive(rule.id, !rule.active);
                          await _load();
                        },
                        icon: Icon(
                          rule.active
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.deleteRule,
                        onPressed: () async {
                          await ref
                              .read(localRecurringRepositoryProvider)
                              .delete(rule.id);
                          await _load();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
