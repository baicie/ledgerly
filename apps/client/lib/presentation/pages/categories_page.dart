import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';
import 'category_editor_page.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  var _type = 'expense';

  String get _typeLabel => _type == 'income' ? '收入' : '支出';

  Future<void> _openEditor({
    CategoryAccountRow? category,
    String? initialParentId,
  }) async {
    final type = category?.type ?? _type;
    final categories = await ref.read(categoryAccountsProvider(type).future);
    if (!mounted) return;
    await showCategoryEditorPage(
      context: context,
      type: type,
      categories: categories,
      category: category,
      initialParentId: initialParentId,
    );
  }

  Future<void> _addCategory() => _openEditor();

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
              data: (rows) {
                final byId = {for (final row in rows) row.id: row};
                final roots = rows
                    .where(
                      (row) =>
                          row.parentAccountId == null ||
                          !byId.containsKey(row.parentAccountId),
                    )
                    .toList();
                final secondLevelCount =
                    rows.where((row) => row.parentAccountId != null).length;
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverToBoxAdapter(
                    child: LedgerlySection(
                      title: '$_typeLabel分类',
                      trailing: Text(
                        '${roots.length} 个一级 · $secondLevelCount 个二级',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                      headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                      child: rows.isEmpty
                          ? LedgerlyEmptyState(
                              icon: Icons.category_outlined,
                              title: '还没有$_typeLabel分类',
                              message: '新建一级分类后即可继续添加二级分类。',
                              action: FilledButton.icon(
                                onPressed: _addCategory,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('新建分类'),
                              ),
                            )
                          : Column(
                              children: [
                                for (var index = 0;
                                    index < roots.length;
                                    index++) ...[
                                  if (index > 0) const Divider(height: 1),
                                  _CategoryGroup(
                                    category: roots[index],
                                    children: rows
                                        .where(
                                          (row) =>
                                              row.parentAccountId ==
                                              roots[index].id,
                                        )
                                        .toList(),
                                    onAddChild: () => _openEditor(
                                      initialParentId: roots[index].id,
                                    ),
                                    onEdit: () => _openEditor(
                                      category: roots[index],
                                    ),
                                    onEditChild: (category) => _openEditor(
                                      category: category,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                );
              },
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

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.category,
    required this.children,
    required this.onAddChild,
    required this.onEdit,
    required this.onEditChild,
  });

  final CategoryAccountRow category;
  final List<CategoryAccountRow> children;
  final VoidCallback onAddChild;
  final VoidCallback onEdit;
  final ValueChanged<CategoryAccountRow> onEditChild;

  @override
  Widget build(BuildContext context) {
    final kind = category.type == 'income'
        ? TransactionSummaryKind.income
        : TransactionSummaryKind.expense;
    final color = ledgerColorFor(category.name, kind: kind);
    return Column(
      children: [
        ColoredBox(
          color: color.withValues(alpha: 0.06),
          child: ListTile(
            key: Key('category-root-${category.id}'),
            minTileHeight: 72,
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            leading: LedgerlyIconBadge(
              icon: ledgerIconFor(category.name, kind: kind),
              color: color,
            ),
            title: Text(
              localizedLedgerName(category.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              children.isEmpty ? '暂无二级分类' : '${children.length} 个二级分类',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('category-add-child-${category.id}'),
                  tooltip: '在${localizedLedgerName(category.name)}下新增二级分类',
                  onPressed: onAddChild,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  key: Key('edit-category-${category.id}'),
                  tooltip: '编辑${localizedLedgerName(category.name)}',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        ),
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(indent: 82, endIndent: 16),
          _SecondLevelCategoryTile(
            category: children[index],
            onEdit: () => onEditChild(children[index]),
          ),
        ],
      ],
    );
  }
}

class _SecondLevelCategoryTile extends StatelessWidget {
  const _SecondLevelCategoryTile({
    required this.category,
    required this.onEdit,
  });

  final CategoryAccountRow category;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final kind = category.type == 'income'
        ? TransactionSummaryKind.income
        : TransactionSummaryKind.expense;
    final color = ledgerColorFor(category.name, kind: kind);
    return ListTile(
      minTileHeight: 58,
      contentPadding: const EdgeInsets.fromLTRB(36, 2, 8, 2),
      leading: LedgerlyIconBadge(
        icon: ledgerIconFor(category.name, kind: kind),
        color: color,
        size: 34,
      ),
      title: Text(
        localizedLedgerName(category.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text('二级分类'),
      trailing: IconButton(
        key: Key('edit-category-${category.id}'),
        tooltip: '编辑${localizedLedgerName(category.name)}',
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}
