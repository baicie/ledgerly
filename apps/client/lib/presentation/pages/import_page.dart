import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/csv_bill_parser.dart';
import '../../data/ledger_repository.dart';
import '../../domain/ids.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _parser = const CsvBillParser();
  List<ImportDraft> _drafts = const [];
  var _busy = false;
  String? _message;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final csv = await ref.read(userFilePortProvider).pickCsvText();
      if (csv == null) return;
      final drafts = _parser.parse(csv);
      setState(() {
        _drafts = drafts;
        _message = drafts.isEmpty ? l10nOf(context).importNothing : null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final selected = [for (final draft in _drafts) if (draft.selected) draft];
    if (selected.isEmpty) {
      setState(() => _message = l10nOf(context).importNothing);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final l10n = l10nOf(context);
      final expenses = await ref.read(categoryAccountsProvider('expense').future);
      final incomes = await ref.read(categoryAccountsProvider('income').future);
      final categories = [
        for (final row in expenses)
          ImportCategory(id: row.id, name: row.name, type: row.type),
        for (final row in incomes)
          ImportCategory(id: row.id, name: row.name, type: row.type),
      ];
      final service = ref.read(ledgerAppServiceProvider);
      final cash = accountKeyCash(defaultBookId);
      var imported = 0;
      for (final draft in selected) {
        final kind = draft.kind == TransactionSummaryKind.income
            ? 'income'
            : 'expense';
        final categoryId = matchImportCategoryId(
          kind: kind,
          rawCategory: draft.rawCategory,
          categories: categories,
          localize: (name) => localizedLedgerName(l10n, name),
        );
        if (categoryId == null) continue;
        if (draft.kind == TransactionSummaryKind.income) {
          await service.createIncome(
            incomeAccountId: categoryId,
            depositAccountId: cash,
            amountMinor: draft.amountMinor,
            description: draft.description,
            occurredAt: draft.occurredAt,
          );
        } else {
          await service.createExpense(
            expenseAccountId: categoryId,
            fundingAccountId: cash,
            amountMinor: draft.amountMinor,
            description: draft.description,
            occurredAt: draft.occurredAt,
          );
        }
        imported += 1;
      }
      invalidateLedgerViews(ref);
      if (!mounted) return;
      setState(() {
        _drafts = const [];
        _message = l10n.importedCount(imported);
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final selectedCount =
        _drafts.where((draft) => draft.selected).length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importCsvTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LedgerlySection(child: Text(l10n.importHelp)),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('import-pick'),
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(_busy ? l10n.processing : l10n.pickCsv),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l10n.importSelectedCount(selectedCount)),
              const SizedBox(height: 8),
              for (var index = 0; index < _drafts.length; index++)
                CheckboxListTile(
                  key: Key('import-draft-$index'),
                  value: _drafts[index].selected,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _drafts[index].selected = value ?? false;
                          });
                        },
                  title: Text(
                    _drafts[index].description.isEmpty
                        ? (_drafts[index].rawCategory ?? l10n.uncategorized)
                        : _drafts[index].description,
                  ),
                  subtitle: Text(
                    '${_drafts[index].occurredAt.toLocal().toIso8601String().split('T').first} · ${formatDisplayMinor(_drafts[index].amountMinor)}',
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('import-confirm'),
                onPressed: _busy ? null : _commit,
                child: Text(l10n.importConfirm),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
