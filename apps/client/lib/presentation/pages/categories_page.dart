import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../category_editor_dialog.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  var _type = 'expense';

  String get _typeLabel => _type == 'income' ? '收入' : '支出';

  Future<void> _addCategory() async {
    await showCategoryEditorDialog(context: context, type: _type);
  }

  Future<void> _editCategory(CategoryAccountRow category) async {
    await showCategoryEditorDialog(
      context: context,
      type: category.type,
      categoryId: category.id,
      initialName: localizedLedgerName(category.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryAccountsProvider(_type));
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          IconButton(
            key: const Key('category-add'),
            tooltip: '新建分类',
            onPressed: _addCategory,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text(
                          '支出',
                          key: Key('category-type-expense'),
                        ),
                        icon: Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text(
                          '收入',
                          key: Key('category-type-income'),
                        ),
                        icon: Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() => _type = selection.single);
                    },
                  ),
                ),
              ),
            ),
            categories.when(
              data: (rows) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                sliver: SliverToBoxAdapter(
                  child: LedgerlySection(
                    title: '$_typeLabel分类',
                    trailing: Text(
                      '${rows.length} 项',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                    headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                    child: rows.isEmpty
                        ? LedgerlyEmptyState(
                            icon: Icons.category_outlined,
                            title: '还没有$_typeLabel分类',
                            message: '新建一个分类后即可开始记账。',
                            action: FilledButton.icon(
                              onPressed: _addCategory,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新建分类'),
                            ),
                          )
                        : Column(
                            children: [
                              for (var index = 0;
                                  index < rows.length;
                                  index++) ...[
                                if (index > 0)
                                  const Divider(indent: 70, endIndent: 16),
                                _CategoryTile(
                                  category: rows[index],
                                  onEdit: () => _editCategory(rows[index]),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: LedgerlyColors.income,
                        ),
                        const SizedBox(height: 8),
                        const Text('分类加载失败'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.invalidate(categoryAccountsProvider(_type)),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onEdit});

  final CategoryAccountRow category;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final kind = category.type == 'income'
        ? TransactionSummaryKind.income
        : TransactionSummaryKind.expense;
    final color = ledgerColorFor(category.name, kind: kind);
    return ListTile(
      minTileHeight: 68,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      leading: LedgerlyIconBadge(
        icon: ledgerIconFor(category.name, kind: kind),
        color: color,
      ),
      title: Text(
        localizedLedgerName(category.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        key: Key('edit-category-${category.id}'),
        tooltip: '编辑${localizedLedgerName(category.name)}',
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}
