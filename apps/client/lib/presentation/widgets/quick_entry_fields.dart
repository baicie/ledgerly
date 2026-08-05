import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../category_editor_dialog.dart';
import '../design/ledgerly_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _rows = widget.rows;
  }

  Future<void> _addCategory() async {
    final categoryId = await showCategoryEditorDialog(
      context: context,
      type: widget.categoryType!,
    );
    if (categoryId != null && mounted) {
      Navigator.pop(context, categoryId);
    }
  }

  Future<void> _editCategory(AccountBalanceRow row) async {
    final categoryId = await showCategoryEditorDialog(
      context: context,
      type: widget.categoryType!,
      categoryId: row.id,
      initialName: localizedLedgerName(row.name),
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
            ),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final gridRows = (_rows.length + 2) ~/ 3;
    final desiredHeight =
        100.0 + (gridRows * 112.0) + (_isCategoryPicker ? 72.0 : 0.0);
    final height = desiredHeight
        .clamp(_isCategoryPicker ? 320.0 : 220.0, maxHeight)
        .toDouble();
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
                    tooltip: _editing ? '完成编辑' : '编辑分类',
                    isSelected: _editing,
                    onPressed: () => setState(() => _editing = !_editing),
                    icon: const Icon(Icons.edit_outlined),
                    selectedIcon: const Icon(Icons.check_rounded),
                  ),
                IconButton(
                  tooltip: '关闭',
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
                          _isCategoryPicker ? '暂无分类' : '暂无可用账户',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 480 ? 4 : 3;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        itemCount: _rows.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: 104,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) =>
                            _buildCategoryTile(_rows[index]),
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
                label: const Text('新增分类'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(AccountBalanceRow row) {
    final selected = row.id == widget.selectedId;
    final color = ledgerColorFor(row.name);
    final name = localizedLedgerName(row.name);
    return Semantics(
      button: true,
      selected: selected,
      label: _editing ? '编辑$name' : '选择$name',
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
