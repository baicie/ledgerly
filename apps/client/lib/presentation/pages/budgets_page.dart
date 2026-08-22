import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/amount_parse.dart';
import '../../data/local_budget_repository.dart';
import '../../domain/ids.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';

BigInt? parseBudgetAmountMinor(String raw) => parsePositiveAmountMinor(raw);

class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  var _busy = false;
  String? _message;
  List<Map<String, dynamic>> _budgets = const [];
  String? _lastCategoryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _remoteBookId() async {
    return ref.read(authRepositoryProvider).currentSession?.bookId;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    try {
      if (ref.read(apiEndpointProvider) == null) {
        await _loadLocal();
        return;
      }
      final bookId = await _remoteBookId();
      if (bookId == null) {
        if (mounted) {
          setState(() => _message = L10n.current.notSignedInBudgets);
        }
        return;
      }
      final list = await ref.read(syncApiProvider).listBudgets(bookId: bookId);
      if (!mounted) return;
      setState(() {
        _budgets = list;
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadLocal() async {
    final records =
        await ref.read(localBudgetRepositoryProvider).list(defaultBookId);
    final transactions = await ref.read(monthTransactionsProvider.future);
    final categories =
        await ref.read(categoryAccountsProvider('expense').future);
    final parentById = {
      for (final category in categories) category.id: category.parentAccountId,
    };
    final list = [
      for (final record in records)
        () {
          final spent = spentForBudget(
            budget: record,
            transactions: transactions,
            parentById: parentById,
          );
          return <String, dynamic>{
            'id': record.id,
            'name': record.name,
            'amountMinor': record.amountMinor.toString(),
            'categoryAccountId': record.categoryAccountId,
            'spentMinor': spent.toString(),
            'remainingMinor': (record.amountMinor - spent).toString(),
          };
        }(),
    ];
    if (!mounted) return;
    setState(() {
      _budgets = list;
      _message = null;
    });
  }

  Future<void> _openCreateSheet(List<CategoryAccountRow> categories) async {
    if (categories.isEmpty) {
      setState(() => _message = L10n.current.createExpenseCategoryFirst);
      return;
    }
    final draft = await showModalBottomSheet<_BudgetDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _BudgetEditor(
        categories: categories,
        initialCategoryId: _lastCategoryId,
        allowAllExpenses: ref.read(apiEndpointProvider) == null,
      ),
    );
    if (draft == null || !mounted) return;
    _lastCategoryId = draft.categoryId;
    await _create(draft);
  }

  Future<void> _create(_BudgetDraft draft) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (ref.read(apiEndpointProvider) == null) {
        await ref.read(localBudgetRepositoryProvider).insert(
              bookId: defaultBookId,
              name: draft.name,
              amountMinor: draft.amountMinor,
              categoryAccountId: draft.categoryId,
            );
        await _load();
        return;
      }
      final bookId = await _remoteBookId();
      if (bookId == null) {
        setState(() => _message = L10n.current.notSignedInCreateBudget);
        return;
      }
      await ref.read(syncApiProvider).createBudget(
            bookId: bookId,
            name: draft.name,
            amountMinor: draft.amountMinor.toString(),
            categoryAccountId: _remoteAccountId(draft.categoryId, bookId),
          );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _remoteAccountId(String localAccountId, String remoteBookId) {
    final separator = localAccountId.indexOf(':');
    if (separator == -1) return localAccountId;
    return '$remoteBookId${localAccountId.substring(separator)}';
  }

  String _categoryLabel(
    AppLocalizations l10n,
    Map<String, dynamic> budget,
    List<CategoryAccountRow> categories,
  ) {
    final remoteId = budget['categoryAccountId']?.toString();
    if (remoteId == null || remoteId.isEmpty) return l10n.allExpenses;
    final key = remoteId.split(':').last;
    for (final category in categories) {
      if (category.id.split(':').last == key) {
        return _categoryDisplayName(l10n, category, categories);
      }
    }
    return l10n.expenseCategory;
  }

  String _categoryDisplayName(
    AppLocalizations l10n,
    CategoryAccountRow category,
    List<CategoryAccountRow> categories,
  ) {
    if (category.parentAccountId == null) {
      return localizedLedgerName(l10n, category.name);
    }
    for (final parent in categories) {
      if (parent.id == category.parentAccountId) {
        return '${localizedLedgerName(l10n, parent.name)} / ${localizedLedgerName(l10n, category.name)}';
      }
    }
    return localizedLedgerName(l10n, category.name);
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('connection')) {
      return L10n.current.cannotReachService;
    }
    return L10n.current.budgetsLoadFailed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final categoriesState = ref.watch(categoryAccountsProvider('expense'));
    final categories =
        categoriesState.valueOrNull ?? const <CategoryAccountRow>[];
    final totals = _budgetTotals();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.budgetTargets),
        actions: [
          IconButton(
            tooltip: l10n.refreshBudgets,
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: l10n.addBudget,
            onPressed: _busy ? null : () => _openCreateSheet(categories),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            if (_message != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: _ErrorBanner(message: _message!, onRetry: _load),
                ),
              ),
            if (_budgets.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                sliver: SliverToBoxAdapter(
                  child: _BudgetSummary(
                    totalLimit: totals.$1,
                    totalSpent: totals.$2,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: _budgets.isEmpty && !_busy
                    ? LedgerlySection(
                        child: LedgerlyEmptyState(
                          icon: Icons.flag_outlined,
                          title: l10n.noBudgets,
                          message: l10n.noBudgetsHint,
                          action: categoriesState.isLoading
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : FilledButton.icon(
                                  onPressed: () => _openCreateSheet(categories),
                                  icon: const Icon(Icons.add_rounded),
                                  label: Text(l10n.setFirstBudget),
                                ),
                        ),
                      )
                    : LedgerlySection(
                        title: l10n.thisMonthTargets,
                        trailing: Text(
                          l10n.itemCount(_budgets.length),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                        headerPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: _busy && _budgets.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(32),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              )
                            : Column(
                                children: [
                                  for (var index = 0;
                                      index < _budgets.length;
                                      index++) ...[
                                    if (index > 0)
                                      const Divider(indent: 16, endIndent: 16),
                                    _BudgetTile(
                                      budget: _budgets[index],
                                      categoryLabel: _categoryLabel(
                                        l10n,
                                        _budgets[index],
                                        categories,
                                      ),
                                      onDelete: ref.watch(apiEndpointProvider) ==
                                              null
                                          ? () => _deleteLocal(
                                                '${_budgets[index]['id']}',
                                              )
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (BigInt, BigInt) _budgetTotals() {
    var limit = BigInt.zero;
    var spent = BigInt.zero;
    for (final budget in _budgets) {
      limit += BigInt.tryParse('${budget['amountMinor']}') ?? BigInt.zero;
      spent += BigInt.tryParse('${budget['spentMinor'] ?? '0'}') ?? BigInt.zero;
    }
    return (limit, spent);
  }

  Future<void> _deleteLocal(String id) async {
    await ref.read(localBudgetRepositoryProvider).delete(id);
    await _load();
  }
}

class _BudgetDraft {
  const _BudgetDraft({
    required this.name,
    required this.amountMinor,
    required this.categoryId,
  });

  final String name;
  final BigInt amountMinor;
  final String categoryId;
}

class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({
    required this.categories,
    this.initialCategoryId,
    this.allowAllExpenses = false,
  });

  final List<CategoryAccountRow> categories;
  final String? initialCategoryId;
  final bool allowAllExpenses;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String _categoryId;
  String? _error;

  CategoryAccountRow? get _category {
    if (_categoryId.isEmpty) return null;
    for (final category in widget.categories) {
      if (category.id == _categoryId) return category;
    }
    return widget.categories.isEmpty ? null : widget.categories.first;
  }

  String _categoryDisplayName(
    AppLocalizations l10n,
    CategoryAccountRow category,
  ) {
    if (category.parentAccountId == null) {
      return localizedLedgerName(l10n, category.name);
    }
    for (final parent in widget.categories) {
      if (parent.id == category.parentAccountId) {
        return '${localizedLedgerName(l10n, parent.name)} / ${localizedLedgerName(l10n, category.name)}';
      }
    }
    return localizedLedgerName(l10n, category.name);
  }

  String _defaultName(AppLocalizations l10n, CategoryAccountRow? category) {
    if (category == null || _categoryId.isEmpty) {
      return l10n.allExpensesBudgetName;
    }
    return l10n.budgetDefaultName(localizedLedgerName(l10n, category.name));
  }

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.any((c) => c.id == widget.initialCategoryId)
        ? widget.initialCategoryId!
        : widget.categories.first.id;
    _name = TextEditingController(
      text: _defaultName(L10n.current, _category),
    );
    _amount = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = l10nOf(context);
    final amount = parseBudgetAmountMinor(_amount.text);
    if (amount == null) {
      setState(() => _error = l10n.enterPositiveDecimalAmount);
      return;
    }
    final name = _name.text.trim().isEmpty
        ? _defaultName(l10n, _category)
        : _name.text.trim();
    Navigator.of(context).pop(
      _BudgetDraft(name: name, amountMinor: amount, categoryId: _categoryId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.setBudgetTarget,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l10n.close,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: InputDecoration(
              labelText: l10n.expenseCategory,
              prefixIcon: const Icon(Icons.category_outlined),
            ),
            items: [
              if (widget.allowAllExpenses)
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n.allExpenses),
                ),
              for (final category in widget.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(_categoryDisplayName(l10n, category)),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              final previousDefault = _defaultName(l10n, _category);
              setState(() {
                _categoryId = value;
                if (_name.text.isEmpty || _name.text == previousDefault) {
                  _name.text = _defaultName(l10n, _category);
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.targetName,
              prefixIcon: const Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.monthlyAmount,
              prefixText: '¥ ',
              prefixIcon: const Icon(Icons.flag_outlined),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.saveTarget),
          ),
        ],
      ),
    );
  }
}

class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.totalLimit, required this.totalSpent});

  final BigInt totalLimit;
  final BigInt totalSpent;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final progress = totalLimit == BigInt.zero
        ? 0.0
        : (totalSpent.toDouble() / totalLimit.toDouble()).clamp(0.0, 1.0);
    final over = totalSpent > totalLimit;
    return LedgerlySection(
      title: l10n.monthTotalTarget,
      trailing: Text(
        over ? l10n.overBudget : '${(progress * 100).round()}%',
        style: TextStyle(
          color: over ? LedgerlyColors.income : LedgerlyColors.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatDisplayMinor(totalSpent),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ ${formatDisplayMinor(totalLimit)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: over ? LedgerlyColors.income : LedgerlyColors.brandMint,
            backgroundColor: LedgerlyColors.divider,
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.budget,
    required this.categoryLabel,
    this.onDelete,
  });

  final Map<String, dynamic> budget;
  final String categoryLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final limit = BigInt.tryParse('${budget['amountMinor']}') ?? BigInt.zero;
    final spent =
        BigInt.tryParse('${budget['spentMinor'] ?? '0'}') ?? BigInt.zero;
    final remaining = BigInt.tryParse('${budget['remainingMinor'] ?? '0'}') ??
        (limit - spent);
    final over = spent > limit;
    final progress = limit == BigInt.zero
        ? 0.0
        : (spent.toDouble() / limit.toDouble()).clamp(0.0, 1.0);
    final color = over ? LedgerlyColors.income : LedgerlyColors.brand;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LedgerlyIconBadge(
                icon: ledgerIconFor(categoryLabel),
                color: ledgerColorFor(categoryLabel),
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${budget['name'] ?? l10n.budgetTarget}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      l10n.monthlyWithCategory(categoryLabel),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                formatDisplayMinor(limit),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: l10n.deleteBudget,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: color,
            backgroundColor: LedgerlyColors.divider,
            borderRadius: BorderRadius.circular(7),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                l10n.spentAmount(formatDisplayMinor(spent)),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              Text(
                over
                    ? l10n.overByAmount(formatDisplayMinor(spent - limit))
                    : l10n.remainingAmount(formatDisplayMinor(remaining)),
                style: TextStyle(
                  color: over ? LedgerlyColors.income : LedgerlyColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LedgerlyColors.actionSurface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: LedgerlyColors.actionStrong),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            IconButton(
              tooltip: l10nOf(context).retry,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
