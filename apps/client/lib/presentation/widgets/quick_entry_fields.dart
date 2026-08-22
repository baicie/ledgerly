import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../pages/category_editor_page.dart';
import '../providers.dart';
import 'ledgerly_finance.dart';

class QuickEntrySelectionField extends StatelessWidget {
  const QuickEntrySelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minTileHeight: 58,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: LedgerlyIconBadge(icon: icon, color: color, size: 34),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

Future<String?> showQuickEntryPicker({
  required BuildContext context,
  required String title,
  required List<AccountBalanceRow> rows,
  required String? selectedId,
  String? categoryType,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _QuickEntryPicker(
      title: title,
      rows: rows,
      selectedId: selectedId,
      categoryType: categoryType,
    ),
  );
}

class _QuickEntryPicker extends ConsumerStatefulWidget {
  const _QuickEntryPicker({
    required this.title,
    required this.rows,
    required this.selectedId,
    this.categoryType,
  });

  final String title;
  final List<AccountBalanceRow> rows;
  final String? selectedId;
  final String? categoryType;

  @override
  ConsumerState<_QuickEntryPicker> createState() => _QuickEntryPickerState();
}

class _QuickEntryPickerState extends ConsumerState<_QuickEntryPicker> {
  late List<AccountBalanceRow> _rows;
  var _editing = false;

  bool get _isCategoryPicker => widget.categoryType != null;

  List<CategoryAccountRow> get _categoryRows => _rows
      .map(
        (row) => CategoryAccountRow(
          id: row.id,
          name: row.name,
          type: row.type,
          parentAccountId: row.parentAccountId,
        ),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _rows = widget.rows;
  }

  Future<void> _addCategory() async {
    final categoryId = await showCategoryEditorPage(
      context: context,
      type: widget.categoryType!,
      categories: _categoryRows,
    );
    if (categoryId != null && mounted) {
      Navigator.pop(context, categoryId);
    }
  }

  Future<void> _editCategory(AccountBalanceRow row) async {
    final categories = _categoryRows;
    final categoryId = await showCategoryEditorPage(
      context: context,
      type: widget.categoryType!,
      categories: categories,
      category: categories.firstWhere((category) => category.id == row.id),
    );
    if (categoryId == null || !mounted) return;

    final refreshed = await ref.refresh(
      categoryAccountsProvider(widget.categoryType!).future,
    );
    if (!mounted) return;
    setState(() {
      _rows = refreshed
          .map(
            (category) => AccountBalanceRow(
              id: category.id,
              name: category.name,
              type: category.type,
              balance: BigInt.zero,
              parentAccountId: category.parentAccountId,
            ),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final gridRows = (_rows.length + 2) ~/ 3;
    final desiredHeight = _isCategoryPicker
        ? 540.0
        : (100.0 + (gridRows * 112.0)).clamp(220.0, 540.0).toDouble();
    final height = desiredHeight > maxHeight ? maxHeight : desiredHeight;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_isCategoryPicker && _rows.isNotEmpty)
                  IconButton(
                    key: const Key('category-edit-toggle'),
                    tooltip:
                        _editing ? l10n.finishEditing : l10n.editCategoryAction,
                    isSelected: _editing,
                    onPressed: () => setState(() => _editing = !_editing),
                    icon: const Icon(Icons.edit_outlined),
                    selectedIcon: const Icon(Icons.check_rounded),
                  ),
                IconButton(
                  tooltip: l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.category_outlined,
                          size: 38,
                          color: LedgerlyColors.disabled,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isCategoryPicker
                              ? l10n.noCategories
                              : l10n.noAccounts,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  )
                : _isCategoryPicker
                    ? _buildCategoryList()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 480 ? 4 : 3;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                            itemCount: _rows.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisExtent: 104,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemBuilder: (context, index) =>
                                _buildGridTile(_rows[index]),
                          );
                        },
                      ),
          ),
          if (_isCategoryPicker)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: OutlinedButton.icon(
                key: const Key('category-add-picker'),
                onPressed: _addCategory,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: Text(l10n.addCategory),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final l10n = l10nOf(context);
    final rows = _orderedCategoryRows();
    final byId = {for (final row in rows) row.id: row};
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const Divider(
        indent: 74,
        endIndent: 20,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final row = rows[index];
        final parent = byId[row.parentAccountId];
        final selected = row.id == widget.selectedId;
        final color = ledgerColorFor(row.name);
        final name = localizedLedgerName(l10n, row.name);
        return ListTile(
          key: Key('quick-category-${row.id}'),
          minTileHeight: 58,
          contentPadding: EdgeInsets.fromLTRB(
            parent == null ? 20 : 40,
            2,
            20,
            2,
          ),
          leading: LedgerlyIconBadge(
            icon: ledgerIconFor(row.name),
            color: color,
            size: parent == null ? 38 : 34,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            parent == null
                ? l10n.firstLevelCategory
                : l10n
                    .parentSecondLevel(localizedLedgerName(l10n, parent.name)),
          ),
          selected: selected,
          selectedTileColor: LedgerlyColors.actionSurface,
          onTap: () =>
              _editing ? _editCategory(row) : Navigator.pop(context, row.id),
          trailing: Icon(
            _editing
                ? Icons.edit_outlined
                : selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
            color: selected ? LedgerlyColors.actionStrong : null,
          ),
        );
      },
    );
  }

  List<AccountBalanceRow> _orderedCategoryRows() {
    final byId = {for (final row in _rows) row.id: row};
    final roots = _rows
        .where(
          (row) =>
              row.parentAccountId == null ||
              !byId.containsKey(row.parentAccountId),
        )
        .toList();
    final result = <AccountBalanceRow>[];
    for (final root in roots) {
      result.add(root);
      result.addAll(
        _rows.where((row) => row.parentAccountId == root.id),
      );
    }
    return result;
  }

  Widget _buildGridTile(AccountBalanceRow row) {
    final l10n = l10nOf(context);
    final selected = row.id == widget.selectedId;
    final color = ledgerColorFor(row.name);
    final name = localizedLedgerName(l10n, row.name);
    return Semantics(
      button: true,
      selected: selected,
      label: _editing ? l10n.editNamed(name) : l10n.selectNamed(name),
      child: Material(
        color: selected ? LedgerlyColors.actionSurface : LedgerlyColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color:
                selected ? LedgerlyColors.actionStrong : LedgerlyColors.divider,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              _editing ? _editCategory(row) : Navigator.pop(context, row.id),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LedgerlyIconBadge(
                      icon: ledgerIconFor(row.name),
                      color: color,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (_editing)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.edit_outlined, size: 17),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
