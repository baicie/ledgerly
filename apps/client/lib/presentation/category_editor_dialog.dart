import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ledger_app_service.dart';
import 'providers.dart';

Future<String?> showCategoryEditorDialog({
  required BuildContext context,
  required String type,
  String? categoryId,
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => CategoryEditorDialog(
      type: type,
      categoryId: categoryId,
      initialName: initialName,
    ),
  );
}

class CategoryEditorDialog extends ConsumerStatefulWidget {
  const CategoryEditorDialog({
    super.key,
    required this.type,
    this.categoryId,
    this.initialName,
  });

  final String type;
  final String? categoryId;
  final String? initialName;

  @override
  ConsumerState<CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<CategoryEditorDialog> {
  late final TextEditingController _name;
  var _saving = false;
  String? _error;

  bool get _editing => widget.categoryId != null;
  String get _typeLabel => widget.type == 'income' ? '收入' : '支出';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final service = ref.read(ledgerAppServiceProvider);
      final String categoryId;
      if (_editing) {
        categoryId = widget.categoryId!;
        await service.renameCategory(
          categoryId: categoryId,
          name: _name.text,
        );
      } else {
        categoryId = await service.createCategory(
          name: _name.text,
          type: widget.type,
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
          _error = '分类保存失败，请稍后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${_editing ? '编辑' : '新建'}$_typeLabel分类'),
      content: TextField(
        key: const Key('category-name-input'),
        controller: _name,
        autofocus: true,
        enabled: !_saving,
        maxLength: 24,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: '分类名称',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
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
              : Icon(_editing ? Icons.check_rounded : Icons.add_rounded),
          label: Text(_saving ? '保存中' : '保存'),
        ),
      ],
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
