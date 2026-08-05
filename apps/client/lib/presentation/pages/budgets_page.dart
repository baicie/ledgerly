import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';

BigInt? parseBudgetAmountMinor(String raw) {
  final value = raw.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final yuan = BigInt.tryParse(parts[0]);
  if (yuan == null) return null;
  final cents = parts.length == 1
      ? BigInt.zero
      : BigInt.tryParse(parts[1].padRight(2, '0'));
  if (cents == null) return null;
  final amount = yuan * BigInt.from(100) + cents;
  return amount > BigInt.zero ? amount : null;
}

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
      final bookId = await _remoteBookId();
      if (bookId == null) {
        if (mounted) setState(() => _message = '尚未登录同步，无法加载预算目标');
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

  Future<void> _openCreateSheet(List<CategoryAccountRow> categories) async {
    if (categories.isEmpty) {
      setState(() => _message = '请先创建一个支出分类，再设置预算目标');
      return;
    }
    final draft = await showModalBottomSheet<_BudgetDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _BudgetEditor(
        categories: categories,
        initialCategoryId: _lastCategoryId,
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
      final bookId = await _remoteBookId();
      if (bookId == null) {
        setState(() => _message = '尚未登录同步，无法创建预算目标');
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
    Map<String, dynamic> budget,
    List<CategoryAccountRow> categories,
  ) {
    final remoteId = budget['categoryAccountId']?.toString();
    if (remoteId == null || remoteId.isEmpty) return '全部支出';
    final key = remoteId.split(':').last;
    for (final category in categories) {
      if (category.id.split(':').last == key) {
        return localizedLedgerName(category.name);
      }
    }
    return '支出分类';
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('connection')) {
      return '无法连接服务，请检查网络后重试';
    }
    return '预算目标加载失败，请稍后重试';
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoryAccountsProvider('expense'));
    final categories =
        categoriesState.valueOrNull ?? const <CategoryAccountRow>[];
    final totals = _budgetTotals();

    return Scaffold(
      appBar: AppBar(
        title: const Text('预算目标'),
        actions: [
          IconButton(
            tooltip: '刷新预算目标',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '新增预算目标',
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
                          title: '还没有预算目标',
                          message: '为支出分类设定每月上限，随时掌握进度。',
                          action: categoriesState.isLoading
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : FilledButton.icon(
                                  onPressed: () => _openCreateSheet(categories),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('设置第一个目标'),
                                ),
                        ),
                      )
                    : LedgerlySection(
                        title: '本月目标',
                        trailing: Text(
                          '${_budgets.length} 项',
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
                                        _budgets[index],
                                        categories,
                                      ),
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
  });

  final List<CategoryAccountRow> categories;
  final String? initialCategoryId;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String _categoryId;
  String? _error;

  CategoryAccountRow get _category => widget.categories.firstWhere(
        (category) => category.id == _categoryId,
        orElse: () => widget.categories.first,
      );

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.any((c) => c.id == widget.initialCategoryId)
        ? widget.initialCategoryId!
        : widget.categories.first.id;
    _name =
        TextEditingController(text: '本月${localizedLedgerName(_category.name)}');
    _amount = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseBudgetAmountMinor(_amount.text);
    if (amount == null) {
      setState(() => _error = '请输入大于 0 且最多两位小数的金额');
      return;
    }
    final name = _name.text.trim().isEmpty
        ? '本月${localizedLedgerName(_category.name)}'
        : _name.text.trim();
    Navigator.of(context).pop(
      _BudgetDraft(name: name, amountMinor: amount, categoryId: _categoryId),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text('设置预算目标',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(
              labelText: '支出分类',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              for (final category in widget.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(localizedLedgerName(category.name)),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _categoryId = value;
                if (_name.text.isEmpty || _name.text.startsWith('本月')) {
                  _name.text = '本月${localizedLedgerName(_category.name)}';
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '目标名称',
              prefixIcon: Icon(Icons.edit_outlined),
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
              labelText: '每月金额',
              prefixText: '¥ ',
              prefixIcon: const Icon(Icons.flag_outlined),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
            label: const Text('保存目标'),
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
    final progress = totalLimit == BigInt.zero
        ? 0.0
        : (totalSpent.toDouble() / totalLimit.toDouble()).clamp(0.0, 1.0);
    final over = totalSpent > totalLimit;
    return LedgerlySection(
      title: '本月总目标',
      trailing: Text(
        over ? '已超出' : '${(progress * 100).round()}%',
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
  const _BudgetTile({required this.budget, required this.categoryLabel});

  final Map<String, dynamic> budget;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
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
                      '${budget['name'] ?? '预算目标'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '每月 · $categoryLabel',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                formatDisplayMinor(limit),
                style: Theme.of(context).textTheme.titleMedium,
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
                '已用 ${formatDisplayMinor(spent)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              Text(
                over
                    ? '超出 ${formatDisplayMinor(spent - limit)}'
                    : '剩余 ${formatDisplayMinor(remaining)}',
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
              tooltip: '重试',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
