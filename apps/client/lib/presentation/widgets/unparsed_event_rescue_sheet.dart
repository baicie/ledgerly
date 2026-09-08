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

/// Result returned by [showUnparsedEventRescueSheet].
class UnparsedRescueResult {
  const UnparsedRescueResult({
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

/// Bottom sheet that lets the user turn an unrecognised payment
/// notification into a real ledger entry.
///
/// The notification metadata (platform, occurredAt, raw text) is locked
/// because we cannot re-derive them. The user picks a category (defaulting
/// to "Other"), fills in the missing amount, and optionally opts in to
/// persisting a merchant rule so that future notifications from the same
/// merchant are auto-posted.
Future<UnparsedRescueResult?> showUnparsedEventRescueSheet({
  required BuildContext context,
  required UnparsedPaymentEvent event,
}) {
  return showModalBottomSheet<UnparsedRescueResult>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _UnparsedRescueSheet(event: event),
  );
}

class _UnparsedRescueSheet extends ConsumerStatefulWidget {
  const _UnparsedRescueSheet({required this.event});

  final UnparsedPaymentEvent event;

  @override
  ConsumerState<_UnparsedRescueSheet> createState() =>
      _UnparsedRescueSheetState();
}

class _UnparsedRescueSheetState
    extends ConsumerState<_UnparsedRescueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();
  late final String _defaultCategoryAccountId;
  String? _selectedCategoryId;
  late String _selectedCategoryLabel;
  bool _learnRule = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _defaultCategoryAccountId = accountKeyOtherExpense(defaultBookId);
    _selectedCategoryId = _defaultCategoryAccountId;
    _selectedCategoryLabel =
        localizedLedgerName(l10nOf(context), 'Other Expense');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _directionLabel(AppLocalizations l10n) {
    switch (widget.event.platform) {
      case 'wechat':
        return l10n.autoLedgerPlatformWechat;
      case 'alipay':
        return l10n.autoLedgerPlatformAlipay;
      default:
        return widget.event.platform ?? l10n.autoLedgerPlatformUnknown;
    }
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
      final service = ref.read(ledgerAppServiceProvider);
      await service.rescueUnparsedEvent(
        direction: 'expense',
        amountMinor: amountMinor,
        merchant: merchant,
        note: noteOrNull,
        occurredAt: widget.event.occurredAt,
        platform: widget.event.platform ?? 'unknown',
        reasonTag: widget.event.reasonTag,
        unparsedEventId: widget.event.id,
        categoryAccountId: categoryId,
      );

      // Persist a merchant rule when the user opted in and the picked
      // category is more specific than the default "Other" bucket.
      MerchantRule? learned;
      final categoryKey = _categoryIdToKey(categoryId);
      final shouldLearn =
          _learnRule && merchant != null && categoryKey != 'acc_other_expense';
      if (shouldLearn) {
        final ruleStore = ref.read(merchantRuleStoreProvider);
        final rule = MerchantRule(
          id: 'user-rule-${widget.event.id}',
          categoryKey: categoryKey,
          needles: [merchant],
        );
        await ruleStore.add(rule);
        learned = rule;
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        UnparsedRescueResult(
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
    if (_isUniqueViolation(error) ||
        raw.contains('UNIQUE') ||
        raw.contains('constraint failed')) {
      return l10nOf(context).autoLedgerRescueAlreadySaved;
    }
    // Strip noisy prefixes like "DomainException(...)" or
    // "SqliteException(...)" so users see only the meaningful tail.
    final match = RegExp(r'\):\s*(.*)$').firstMatch(raw);
    final cleaned = match?.group(1)?.trim();
    if (cleaned != null && cleaned.isNotEmpty) return cleaned;
    return raw;
  }

  bool _isUniqueViolation(Object error) {
    final msg = error.toString();
    return msg.contains('UNIQUE constraint failed') ||
        msg.contains('constraint failed');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final event = widget.event;
    final showLearnOption = _merchantController.text.trim().isNotEmpty;
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
                    l10n.autoLedgerRescueTitle,
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
            Text(
              l10n.autoLedgerRescueReason(event.reasonTag),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            _MetaRow(
              label: l10n.autoLedgerRescuePlatform,
              value: _directionLabel(l10n),
            ),
            _MetaRow(
              label: l10n.autoLedgerRescueTime,
              value: event.occurredAt.toLocal().toString().substring(0, 16),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('unparsed-rescue-amount'),
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.amountYuan,
                border: const OutlineInputBorder(),
                prefixText: '¥ ',
              ),
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
              key: const Key('unparsed-rescue-merchant'),
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
              value: _selectedCategoryLabel,
              icon: Icons.category_outlined,
              color: theme.colorScheme.secondary,
              onTap: _submitting ? null : _pickCategory,
            ),
            if (showLearnOption) ...[
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                key: const Key('unparsed-rescue-learn-rule'),
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
              key: const Key('unparsed-rescue-note'),
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.note,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
                    l10n.autoLedgerRescueRawLabel,
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.rawText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('unparsed-rescue-submit'),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.autoLedgerRescueSubmit),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}