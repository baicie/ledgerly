import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/amount_parse.dart';
import '../../application/merchant_classifier.dart';
import '../../domain/ids.dart';
import '../../l10n/l10n.dart';
import '../../services/payment_notification_service.dart';
import '../providers.dart';
import 'quick_entry_fields.dart';

/// Result returned by [showBulkUnparsedRescueSheet].
class BulkUnparsedRescueResult {
  const BulkUnparsedRescueResult({
    required this.amountMinor,
    required this.merchant,
    required this.note,
    required this.categoryAccountId,
    required this.learnedRule,
  });

  final BigInt amountMinor;
  final String? merchant;
  final String? note;
  final String categoryAccountId;
  final MerchantRule? learnedRule;
}

/// Bottom sheet that lets the user rescue a batch of unrecognised
/// notifications at once.
///
/// The user enters a single amount (since all picked events share the
/// same context, e.g. the same merchant billed several times), one
/// shared merchant label and category. Each event is then posted
/// individually with its own event id and fingerprint so server-side
/// deduplication stays intact.
Future<BulkUnparsedRescueResult?> showBulkUnparsedRescueSheet({
  required BuildContext context,
  required List<UnparsedPaymentEvent> events,
}) {
  if (events.isEmpty) return Future.value(null);
  return showModalBottomSheet<BulkUnparsedRescueResult>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _BulkUnparsedRescueSheet(events: events),
  );
}

class _BulkUnparsedRescueSheet extends ConsumerStatefulWidget {
  const _BulkUnparsedRescueSheet({required this.events});

  final List<UnparsedPaymentEvent> events;

  @override
  ConsumerState<_BulkUnparsedRescueSheet> createState() =>
      _BulkUnparsedRescueSheetState();
}

class _BulkUnparsedRescueSheetState
    extends ConsumerState<_BulkUnparsedRescueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();
  late final String _defaultCategoryAccountId;
  String? _selectedCategoryId;
  String? _selectedCategoryLabel;
  bool _learnRule = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _defaultCategoryAccountId = accountKeyOtherExpense(defaultBookId);
    _selectedCategoryId = _defaultCategoryAccountId;
    // The category label needs Localizations, which isn't ready in
    // initState. Schedule a microtask so it runs after the element is
    // mounted and the Localizations scope is reachable via context.
    Future.microtask(() {
      if (!mounted) return;
      setState(() {
        _selectedCategoryLabel =
            localizedLedgerName(l10nOf(context), 'Other Expense');
      });
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _categoryIdToKey(String accountId) {
    final bookId = defaultBookId;
    if (!accountId.startsWith('$bookId:')) return accountId;
    return accountId.substring('$bookId:'.length);
  }

  Future<void> _pickCategory() async {
    if (!mounted) return;
    final l10n = l10nOf(context);
    final categories = await ref.read(
      categoryAccountsProvider('expense').future,
    );
    if (!mounted) return;
    final accountRows = categories
        .map(
          (c) => AccountBalanceRow(
            id: c.id,
            name: c.name,
            type: c.type,
            balance: BigInt.zero,
            parentAccountId: c.parentAccountId,
          ),
        )
        .toList();
    final selected = await showQuickEntryPicker(
      context: context,
      title: l10n.autoLedgerRescueCategoryLabel,
      rows: accountRows,
      selectedId: _selectedCategoryId,
      categoryType: 'expense',
    );
    if (selected == null || !mounted) return;
    final match = categories.firstWhere(
      (row) => row.id == selected,
      orElse: () => categories.first,
    );
    setState(() {
      _selectedCategoryId = match.id;
      _selectedCategoryLabel = localizedLedgerName(l10n, match.name);
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amountText = _amountController.text.trim();
    final amountMinor = parsePositiveAmountMinor(amountText);
    if (amountMinor == null || amountMinor <= BigInt.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).amountInvalid)),
      );
      return;
    }
    final merchantRaw = _merchantController.text.trim();
    final merchant = merchantRaw.isEmpty ? null : merchantRaw;
    final note = _noteController.text.trim();
    final noteOrNull = note.isEmpty ? null : note;
    final categoryId = _selectedCategoryId ?? _defaultCategoryAccountId;

    setState(() => _submitting = true);
    try {
      MerchantRule? learned;
      final categoryKey = _categoryIdToKey(categoryId);
      final shouldLearn = _learnRule &&
          merchant != null &&
          categoryKey != 'acc_other_expense';
      if (shouldLearn) {
        // Pick a stable base id; events already carry unique ids so we
        // namespace the rule by the first event's id to avoid clashes
        // with single-event rescues done earlier.
        final ruleStore = ref.read(merchantRuleStoreProvider);
        final rule = MerchantRule(
          id: 'user-rule-bulk-${widget.events.first.id}',
          categoryKey: categoryKey,
          needles: [merchant],
        );
        await ruleStore.add(rule);
        learned = rule;
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        BulkUnparsedRescueResult(
          amountMinor: amountMinor,
          merchant: merchant,
          note: noteOrNull,
          categoryAccountId: categoryId,
          learnedRule: learned,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('UNIQUE') || raw.contains('constraint failed')) {
      return l10nOf(context).autoLedgerRescueAlreadySaved;
    }
    final match = RegExp(r'\):\s*(.*)$').firstMatch(raw);
    final cleaned = match?.group(1)?.trim();
    if (cleaned != null && cleaned.isNotEmpty) return cleaned;
    return raw;
  }

  /// Renders the running preview "X 笔 × ¥Y = ¥Z" as the user types.
  /// Returns null when no amount has been entered yet so the caller can
  /// hide the line entirely (instead of showing "0 笔 = ¥0").
  String? _previewTotalText(AppLocalizations l10n, int count) {
    final amountMinor = parsePositiveAmountMinor(_amountController.text);
    if (amountMinor == null) return null;
    final unit = _formatYuan(amountMinor);
    final total = _formatYuan(amountMinor * BigInt.from(count));
    return l10n.autoLedgerBulkRescueTotalPreview(count, unit, total);
  }

  static String _formatYuan(BigInt minor) {
    final negative = minor < BigInt.zero;
    final abs = minor.abs();
    final yuan = abs ~/ BigInt.from(100);
    final cents = (abs % BigInt.from(100)).toString().padLeft(2, '0');
    final body = cents == '00' ? '$yuan' : '$yuan.$cents';
    return negative ? '-$body' : body;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final showLearnOption = _merchantController.text.trim().isNotEmpty;
    final count = widget.events.length;
    final byReason = <String, int>{};
    for (final event in widget.events) {
      byReason[event.reasonTag] = (byReason[event.reasonTag] ?? 0) + 1;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.autoLedgerBulkRescueTitle(count),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.close,
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Per-reason summary.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.autoLedgerBulkRescueSummary(count),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  for (final entry in byReason.entries)
                    Text(
                      '• ${entry.key} × ${entry.value}',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  // Live total preview. Empty until the user types a
                  // valid amount so we never display "0 笔 × ¥0".
                  Builder(
                    builder: (_) {
                      final preview = _previewTotalText(l10n, count);
                      if (preview == null) return const SizedBox.shrink();
                      return Row(
                        key: const Key('bulk-rescue-total-preview'),
                        children: [
                          Icon(
                            Icons.calculate_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              preview,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('bulk-rescue-amount'),
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.amountYuan,
                helperText: l10n.autoLedgerBulkRescueAmountHint(count),
                border: const OutlineInputBorder(),
                prefixText: '¥ ',
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.amountRequired;
                }
                final minor = parsePositiveAmountMinor(value.trim());
                if (minor == null) {
                  return l10n.amountInvalid;
                }
                if (minor <= BigInt.zero) {
                  return l10n.amountMustBePositive;
                }
                return null;
              },
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('bulk-rescue-merchant'),
              controller: _merchantController,
              decoration: InputDecoration(
                labelText: l10n.merchantOptional,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            QuickEntrySelectionField(
              label: l10n.autoLedgerRescueCategoryLabel,
              value: _selectedCategoryLabel ?? 'Other Expense',
              icon: Icons.category_outlined,
              color: theme.colorScheme.secondary,
              onTap: _submitting ? null : _pickCategory,
            ),
            if (showLearnOption) ...[
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                key: const Key('bulk-rescue-learn-rule'),
                value: _learnRule,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _learnRule = value),
                title: Text(l10n.autoLedgerRescueLearnRule),
                subtitle: Text(l10n.autoLedgerRescueLearnRuleHint),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('bulk-rescue-note'),
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.note,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('bulk-rescue-submit'),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.autoLedgerBulkRescueConfirm(count)),
            ),
          ],
        ),
      ),
    );
  }
}
