import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ledger_app_service.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

Future<String?> showCategoryEditorPage({
  required BuildContext context,
  required String type,
  required List<CategoryAccountRow> categories,
  CategoryAccountRow? category,
  String? initialParentId,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (context) => CategoryEditorPage(
        type: type,
        categories: categories,
        category: category,
        initialParentId: initialParentId,
      ),
    ),
  );
}

class CategoryEditorPage extends ConsumerStatefulWidget {
  const CategoryEditorPage({
    super.key,
    required this.type,
    required this.categories,
    this.category,
    this.initialParentId,
  });

  final String type;
  final List<CategoryAccountRow> categories;
  final CategoryAccountRow? category;
  final String? initialParentId;

  @override
  ConsumerState<CategoryEditorPage> createState() => _CategoryEditorPageState();
}

class _CategoryEditorPageState extends ConsumerState<CategoryEditorPage> {
  late final TextEditingController _name;
  late bool _secondLevel;
  String? _parentId;
  var _saving = false;
  String? _error;

  bool get _editing => widget.category != null;
  bool get _hasChildren =>
      widget.category != null &&
      widget.categories.any(
        (category) => category.parentAccountId == widget.category!.id,
      );

  List<CategoryAccountRow> get _roots => widget.categories
      .where(
        (category) =>
            category.parentAccountId == null &&
            category.id != widget.category?.id,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    final initialParentId =
        widget.category?.parentAccountId ?? widget.initialParentId;
    _name = TextEditingController(
      text: widget.category == null
          ? ''
          : localizedLedgerName(L10n.current, widget.category!.name),
    );
    _secondLevel = initialParentId != null;
    _parentId = initialParentId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setLevel(bool secondLevel) {
    if (_saving || (secondLevel && _hasChildren)) return;
    setState(() {
      _secondLevel = secondLevel;
      _parentId = secondLevel
          ? (_roots.any((root) => root.id == _parentId)
              ? _parentId
              : _roots.firstOrNull?.id)
          : null;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_secondLevel && _parentId == null) {
      setState(() => _error = l10nOf(context).needParentCategoryFirst);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final service = ref.read(ledgerAppServiceProvider);
      final String categoryId;
      if (_editing) {
        categoryId = widget.category!.id;
        await service.updateCategory(
          categoryId: categoryId,
          name: _name.text,
          parentCategoryId: _secondLevel ? _parentId : null,
        );
      } else {
        categoryId = await service.createCategory(
          name: _name.text,
          type: widget.type,
          parentCategoryId: _secondLevel ? _parentId : null,
        );
      }
      invalidateCategoryData(ref, widget.type);
      if (mounted) Navigator.pop(context, categoryId);
    } on CategoryValidationException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = l10nOf(context).categorySaveFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final typeLabel = widget.type == 'income' ? l10n.income : l10n.expense;
    final roots = _roots;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? l10n.editCategory : l10n.newCategory),
        ),
        body: SafeArea(
          top: false,
          child: LedgerlyContent(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: LedgerlySection(
                    title: l10n.categoryInfo,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('category-name-input'),
                          controller: _name,
                          autofocus: !_editing,
                          enabled: !_saving,
                          maxLength: 24,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _save(),
                          decoration: InputDecoration(
                            labelText: l10n.categoryName,
                            prefixIcon: const Icon(Icons.edit_outlined),
                            errorText: _error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: InputDecoration(
                            labelText: l10n.flowType,
                            prefixIcon: const Icon(Icons.swap_vert_rounded),
                          ),
                          child: Text(l10n.categoryTypeHeading(typeLabel)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.categoryLevel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                label: Text(l10n.firstLevelCategory),
                                icon: const Icon(Icons.account_tree_outlined),
                              ),
                              ButtonSegment(
                                value: true,
                                enabled: !_hasChildren && roots.isNotEmpty,
                                label: Text(l10n.secondLevelCategory),
                                icon: const Icon(
                                  Icons.subdirectory_arrow_right,
                                ),
                              ),
                            ],
                            selected: {_secondLevel},
                            showSelectedIcon: false,
                            onSelectionChanged: _saving
                                ? null
                                : (selection) => _setLevel(selection.single),
                          ),
                        ),
                        if (_secondLevel) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: const Key('category-parent-field'),
                            initialValue: _parentId,
                            decoration: InputDecoration(
                              labelText: l10n.parentCategory,
                              prefixIcon:
                                  const Icon(Icons.account_tree_outlined),
                            ),
                            items: [
                              for (final root in roots)
                                DropdownMenuItem(
                                  value: root.id,
                                  child: Text(
                                    localizedLedgerName(l10n, root.name),
                                  ),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _parentId = value),
                          ),
                        ],
                        if (_hasChildren) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(l10n.categoryHasChildrenKeepRoot),
                              ),
                            ],
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('category-save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? l10n.saving : l10n.save),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void invalidateCategoryData(WidgetRef ref, String type) {
  ref.invalidate(categoryAccountsProvider(type));
  ref.invalidate(accountBalancesProvider);
  ref.invalidate(transactionListProvider);
  ref.invalidate(monthTransactionsProvider);
  ref.invalidate(monthlyLedgerSummaryProvider);
  ref.invalidate(categoryReportProvider);
}
