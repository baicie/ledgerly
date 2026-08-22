import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../../l10n/l10n.dart';
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
    final l10n = l10nOf(context);
    final typeLabel = _type == 'income' ? l10n.income : l10n.expense;
    final categories = ref.watch(categoryAccountsProvider(_type));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.categoryManagement),
        actions: [
          IconButton(
            key: const Key('category-add'),
            tooltip: l10n.newCategory,
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
                    segments: [
                      ButtonSegment(
                        value: 'expense',
                        label: Text(
                          l10n.expense,
                          key: const Key('category-type-expense'),
                        ),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text(
                          l10n.income,
                          key: const Key('category-type-income'),
                        ),
                        icon: const Icon(Icons.arrow_downward_rounded),
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
                      title: l10n.categoryTypeHeading(typeLabel),
                      trailing: Text(
                        l10n.categoryLevelCounts(
                          roots.length,
                          secondLevelCount,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                      headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                      child: rows.isEmpty
                          ? LedgerlyEmptyState(
                              icon: Icons.category_outlined,
                              title: l10n.noCategoriesOfType(typeLabel),
                              message: l10n.noCategoriesHint,
                              action: FilledButton.icon(
                                onPressed: _addCategory,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(l10n.newCategory),
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
                        Text(l10n.categoriesLoadFailed),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.invalidate(categoryAccountsProvider(_type)),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(l10n.retry),
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
    final l10n = l10nOf(context);
    final name = localizedLedgerName(l10n, category.name);
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
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              children.isEmpty
                  ? l10n.noSecondLevelCategories
                  : l10n.secondLevelCount(children.length),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('category-add-child-${category.id}'),
                  tooltip: l10n.addChildCategoryUnder(name),
                  onPressed: onAddChild,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  key: Key('edit-category-${category.id}'),
                  tooltip: l10n.editNamedCategory(name),
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
    final l10n = l10nOf(context);
    final name = localizedLedgerName(l10n, category.name);
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
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(l10n.secondLevelCategory),
      trailing: IconButton(
        key: Key('edit-category-${category.id}'),
        tooltip: l10n.editNamedCategory(name),
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}
