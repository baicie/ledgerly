import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/merchant_classifier.dart';
import '../../domain/default_categories.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

/// Lets users add, edit, and remove their own merchant classification rules.
///
/// User-defined rules always win over the built-in defaults when listed
/// first, so the most useful workflow is:
///
/// 1. Sync a pending notification to see how the built-in rule classifies it.
/// 2. If the classification is wrong, add a user rule for that merchant.
class MerchantRulesPage extends ConsumerStatefulWidget {
  const MerchantRulesPage({super.key});

  @override
  ConsumerState<MerchantRulesPage> createState() =>
      _MerchantRulesPageState();
}

class _MerchantRulesPageState extends ConsumerState<MerchantRulesPage> {
  late Future<List<MerchantRule>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MerchantRule>> _load() async {
    final store = ref.read(merchantRuleStoreProvider);
    return store.load();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _addRule() async {
    final created = await showMerchantRuleEditor(
      context: context,
      bookId: ref.read(selectedBookIdProvider),
      existing: null,
    );
    if (created == null) return;
    await ref.read(merchantRuleStoreProvider).add(created);
    if (!mounted) return;
    _reload();
  }

  Future<void> _editRule(MerchantRule rule) async {
    final updated = await showMerchantRuleEditor(
      context: context,
      bookId: ref.read(selectedBookIdProvider),
      existing: rule,
    );
    if (updated == null) return;
    // Replace by id: remove the existing then add the updated copy so the
    // ordering reflects the user's edit history.
    await ref.read(merchantRuleStoreProvider).remove(rule.id ?? '');
    await ref.read(merchantRuleStoreProvider).add(updated);
    if (!mounted) return;
    _reload();
  }

  Future<void> _deleteRule(MerchantRule rule) async {
    final l10n = l10nOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.autoLedgerRuleDeleteTitle),
        content: Text(l10n.autoLedgerRuleDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            key: const Key('merchant-rule-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || rule.id == null) return;
    await ref.read(merchantRuleStoreProvider).remove(rule.id!);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.autoLedgerRulesTitle),
        actions: [
          IconButton(
            key: const Key('merchant-rule-add'),
            tooltip: l10n.autoLedgerRuleAdd,
            onPressed: _addRule,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            SliverToBoxAdapter(
              child: LedgerlyPageHeader(
                title: l10n.autoLedgerRulesTitle,
                subtitle: l10n.autoLedgerRulesSubtitle,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: FutureBuilder<List<MerchantRule>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final rules = snapshot.data ?? const [];
                    return LedgerlySection(
                      child: _buildRules(l10n, rules),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRules(AppLocalizations l10n, List<MerchantRule> rules) {
    if (rules.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.rule_outlined),
        title: Text(l10n.autoLedgerRulesEmpty),
        subtitle: Text(l10n.autoLedgerRulesEmptyHint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rule in rules) ...[
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(
              localizedDefaultCategoryName(_labelFor(rule.categoryKey)) ??
                  rule.categoryKey,
            ),
            subtitle: Text(
              rule.needles.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              key: Key('merchant-rule-menu-${rule.id ?? ''}'),
              onSelected: (value) {
                if (value == 'edit') {
                  _editRule(rule);
                } else if (value == 'delete') {
                  _deleteRule(rule);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(l10n.edit),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  String _labelFor(String categoryKey) {
    // The keys we expose to the classifier are short ids like "acc_food";
    // they map 1:1 to the DefaultCategoryDefinition.label when present.
    for (final def in defaultCategoryDefinitions) {
      if (def.key == categoryKey) return def.label;
    }
    return categoryKey;
  }
}

/// Modal bottom-sheet editor for creating / editing a single merchant rule.
///
/// On success returns a non-null [MerchantRule]; cancelling returns null.
Future<MerchantRule?> showMerchantRuleEditor({
  required BuildContext context,
  required String bookId,
  MerchantRule? existing,
}) async {
  return showModalBottomSheet<MerchantRule>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _MerchantRuleEditor(bookId: bookId, existing: existing),
      );
    },
  );
}

class _MerchantRuleEditor extends StatefulWidget {
  const _MerchantRuleEditor({required this.bookId, this.existing});

  final String bookId;
  final MerchantRule? existing;

  @override
  State<_MerchantRuleEditor> createState() => _MerchantRuleEditorState();
}

class _MerchantRuleEditorState extends State<_MerchantRuleEditor> {
  final _needlesController = TextEditingController();
  String? _categoryKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _needlesController.text = existing.needles.join(', ');
      _categoryKey = existing.categoryKey;
    }
  }

  @override
  void dispose() {
    _needlesController.dispose();
    super.dispose();
  }

  String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toString();
    final id = 'rule-$ts';
    // Sanitize: keep only safe URL characters (we don't store a URL but
    // it's a familiar filter and easy to reason about).
    final sanitized = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return widget.existing?.id ?? sanitized;
  }

  Future<void> _save() async {
    final l10n = l10nOf(context);
    final needlesRaw = _needlesController.text.trim();
    final needles = needlesRaw
        .split(RegExp(r'[,,;；\n]+'))
        .map((needle) => needle.trim())
        .where((needle) => needle.isNotEmpty)
        .toList();
    if (_categoryKey == null) {
      setState(() => _error = l10n.autoLedgerRuleChooseCategory);
      return;
    }
    if (needles.isEmpty) {
      setState(() => _error = l10n.autoLedgerRuleNeedNeedle);
      return;
    }
    final rule = MerchantRule(
      id: _generateId(),
      categoryKey: _categoryKey!,
      needles: needles,
    );
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final isEdit = widget.existing != null;
    // Show only top-level categories as quick picks; subcategories inherit
    // their parent's id via the seed migration and the classifier falls
    // back through them automatically.
    final rootCategories = defaultCategoryDefinitions
        .where((def) => def.isRoot)
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit
                  ? l10n.autoLedgerRuleEditTitle
                  : l10n.autoLedgerRuleAddTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('merchant-rule-needles'),
              controller: _needlesController,
              maxLines: 2,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              decoration: InputDecoration(
                labelText: l10n.autoLedgerRuleNeedlesLabel,
                helperText: l10n.autoLedgerRuleNeedlesHelper,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('merchant-rule-category'),
              initialValue: _categoryKey,
              decoration: InputDecoration(
                labelText: l10n.autoLedgerRuleCategoryLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final def in rootCategories)
                  DropdownMenuItem(
                    value: def.key,
                    child: Text(def.label),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryKey = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('merchant-rule-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('merchant-rule-save'),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(isEdit ? l10n.save : l10n.create),
            ),
          ],
        ),
      ),
    );
  }
}
