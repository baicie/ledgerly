import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/auto_ledger_service.dart';
import '../../l10n/l10n.dart';
import '../../services/payment_notification_service.dart';
import '../providers.dart';
import '../widgets/bulk_unparsed_rescue_sheet.dart';
import '../widgets/ledgerly_layout.dart';
import '../widgets/unparsed_event_rescue_sheet.dart';

/// Surfaces the auto-ledger state (notification access + pending queue) and
/// provides manual triggers for opening the system settings and forcing a
/// sync. Designed to be reachable from Settings.
class AutoLedgerSettingsPage extends ConsumerStatefulWidget {
  const AutoLedgerSettingsPage({super.key});

  @override
  ConsumerState<AutoLedgerSettingsPage> createState() =>
      _AutoLedgerSettingsPageState();
}

class _AutoLedgerSettingsPageState
    extends ConsumerState<AutoLedgerSettingsPage> {
  PaymentNotificationGateway get _notifications =>
      ref.read(paymentNotificationGatewayProvider);

  bool? _granted;
  List<PendingPaymentEvent> _pending = const [];
  List<UnparsedPaymentEvent> _unparsed = const [];
  /// Current unparsed list after the reason filter has been applied.
  /// Populated at the start of [build] so the AppBar "Select all" and
  /// the list body share the same scope.
  List<UnparsedPaymentEvent> _filteredUnparsed = const [];
  bool _loading = true;
  bool _syncing = false;
  String? _status;
  String? _error;
  /// If non-null, the unparsed list is filtered to show only this reason.
  /// Null means "show all".
  String? _reasonFilter;
  /// Count of user-defined merchant rules loaded from the rule store.
  int _userRuleCount = 0;
  /// Set of unparsed event ids currently in selection mode. Empty means
  /// the list is in normal (single-tap rescue) mode.
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final granted = await _notifications.isAccessEnabled();
      final pending = await _notifications.getPendingEvents();
      final unparsed = await _notifications.getUnparsedEvents();
      // Load user-defined rule count so we can show a badge on the rules link.
      final rules = await ref.read(merchantRuleStoreProvider).load();
      final userRules = rules.where((r) => r.id != null).length;
      if (!mounted) return;
      setState(() {
        _granted = granted;
        _pending = pending;
        _unparsed = unparsed;
        _userRuleCount = userRules;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openSettings() async {
    await _notifications.openAccessSettings();
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _status = null;
    });
    try {
      final report = await ref.read(autoLedgerSyncProvider.future);
      if (!mounted) return;
      setState(() {
        _status = l10nOf(context).autoLedgerSyncSummary(
          report.posted,
          report.duplicates,
          report.skipped,
        );
        _syncing = false;
      });
      invalidateLedgerViews(ref);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _status = error.toString();
      });
    }
  }

  Future<void> _dismissUnparsed() async {
    await _notifications.clearUnparsedEvents();
    await _refresh();
  }

  Future<void> _rescueEvent(UnparsedPaymentEvent event) async {
    final result = await showUnparsedEventRescueSheet(
      context: context,
      event: event,
    );
    if (!mounted || result == null) return;
    // Drop only this entry from the native queue so the other unparsed
    // notifications (if any) stay visible and can be rescued too.
    await _notifications.dismissUnparsedEvent(event.id);
    setState(() {
      _unparsed = _unparsed.where((e) => e.id != event.id).toList();
      if (_reasonFilter != null &&
          !_unparsed.any((e) => e.reasonTag == _reasonFilter)) {
        // The current filter bucket is now empty; fall back to All so the
        // user can still see the remaining unparsed entries.
        _reasonFilter = null;
      }
      if (result.learnedRule != null) {
        _userRuleCount += 1;
      }
    });
    invalidateLedgerViews(ref);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final l10n = l10nOf(context);
    if (result.learnedRule != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.autoLedgerRescueLearnRuleToast),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.autoLedgerRescueSubmit)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final inSelection = _selectedIds.isNotEmpty;
    // Apply the reason filter once so both the AppBar "Select all" and
    // the list body agree on which items are eligible.
    final filteredUnparsed = _reasonFilter == null
        ? _unparsed
        : _unparsed.where((e) => e.reasonTag == _reasonFilter).toList();
    _filteredUnparsed = filteredUnparsed;
    return Scaffold(
      appBar: AppBar(
        title: inSelection
            ? Text(l10n.autoLedgerBulkSelectedCount(_selectedIds.length))
            : Text(l10n.autoLedgerTitle),
        leading: inSelection
            ? IconButton(
                key: const Key('auto-ledger-bulk-exit'),
                tooltip: l10n.cancel,
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selectedIds.clear),
              )
            : null,
        actions: [
          if (inSelection) ...[
            TextButton.icon(
              key: const Key('auto-ledger-bulk-select-all'),
              onPressed: () {
                setState(() {
                  _selectedIds.addAll(_filteredUnparsed.map((e) => e.id));
                });
              },
              icon: const Icon(Icons.select_all),
              label: Text(l10n.selectAll),
            ),
            TextButton(
              key: const Key('auto-ledger-bulk-clear'),
              onPressed: () => setState(_selectedIds.clear),
              child: Text(l10n.autoLedgerBulkClear),
            ),
          ],
        ],
      ),
      bottomNavigationBar: inSelection
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: FilledButton.icon(
                  key: const Key('auto-ledger-bulk-rescue'),
                  onPressed: _bulkRescueSelected,
                  icon: const Icon(Icons.playlist_add_check_rounded),
                  label:
                      Text(l10n.autoLedgerBulkRescue(_selectedIds.length)),
                ),
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            SliverToBoxAdapter(
              child: LedgerlyPageHeader(
                title: l10n.autoLedgerTitle,
                subtitle: l10n.autoLedgerSubtitle,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverToBoxAdapter(
                child: _buildBacklogBanner(l10n),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  child: _buildAccessCard(l10n),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  child: _buildPendingCard(l10n),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  child: _buildUnparsedCard(l10n),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  child: _buildActions(l10n),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  child: _buildRulesLink(l10n),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBacklogBanner(AppLocalizations l10n) {
    if (_loading || _unparsed.isEmpty) return const SizedBox.shrink();
    final n = _unparsed.length;
    final theme = Theme.of(context);
    // Determine the dominant reason to give the user a hint about which
    // parser rule might need attention.
    String? dominantReason;
    int dominantCount = 0;
    final grouped = <String, int>{};
    for (final event in _unparsed) {
      grouped[event.reasonTag] = (grouped[event.reasonTag] ?? 0) + 1;
    }
    for (final entry in grouped.entries) {
      if (entry.value > dominantCount) {
        dominantCount = entry.value;
        dominantReason = entry.key;
      }
    }
    // Severity buckets.
    final isHigh = n >= 10;
    final isMedium = n >= 5;
    if (!isMedium) return const SizedBox.shrink();
    final isDominant =
        dominantReason != null && dominantCount * 2 >= n;
    final scheme = isHigh
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final onScheme = isHigh
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;
    return Material(
      key: const Key('auto-ledger-backlog-banner'),
      color: scheme,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isHigh
                  ? Icons.warning_amber_rounded
                  : Icons.notifications_active_outlined,
              color: onScheme,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.autoLedgerBacklogTitle(n),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: onScheme,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isDominant) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.autoLedgerBacklogDominantHint(
                        dominantReason,
                        dominantCount,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onScheme,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              key: const Key('auto-ledger-backlog-action'),
              onPressed: () {
                // Scroll the user to the unparsed section. We approximate
                // this by switching the reason filter to "all" so the
                // unparsed card is the obvious next thing on the page.
                setState(() => _reasonFilter = null);
              },
              child: Text(
                l10n.autoLedgerBacklogAction,
                style: TextStyle(color: onScheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessCard(AppLocalizations l10n) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(l10n.autoLedgerFailed),
        subtitle: Text(_error!),
      );
    }
    final granted = _granted ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(
            granted
                ? Icons.check_circle_outline
                : Icons.notifications_off_outlined,
            color: granted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            granted ? l10n.autoLedgerGranted : l10n.autoLedgerNotGranted,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('auto-ledger-open-settings'),
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
          label: Text(l10n.autoLedgerOpenSettings),
        ),
      ],
    );
  }

  Widget _buildPendingCard(AppLocalizations l10n) {
    if (_loading) return const SizedBox.shrink();
    if (_pending.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.inbox_outlined),
        title: Text(l10n.autoLedgerEmpty),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.autoLedgerPendingCount(_pending.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final event in _pending.take(20))
          ListTile(
            leading: Icon(
              event.direction == 'income'
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
            ),
            title: Text(
              (event.merchant?.isNotEmpty ?? false)
                  ? event.merchant!
                  : event.platform,
            ),
            subtitle: Text(
              '${event.direction} · ${event.amountMinor ~/ 100}'
              '.${(event.amountMinor % 100).toString().padLeft(2, '0')}',
            ),
            trailing: Text(
              event.occurredAt.toLocal().toString().substring(11, 16),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildUnparsedCard(AppLocalizations l10n) {
    if (_loading) return const SizedBox.shrink();
    if (_unparsed.isEmpty) {
      return ListTile(
        key: const Key('auto-ledger-unparsed-empty'),
        leading: const Icon(Icons.help_outline),
        title: Text(l10n.autoLedgerUnparsedEmpty),
        subtitle: Text(l10n.autoLedgerUnparsedEmptyHint),
      );
    }

    // Group by reason tag to build filter chips.
    final grouped = <String, int>{};
    for (final event in _unparsed) {
      grouped[event.reasonTag] = (grouped[event.reasonTag] ?? 0) + 1;
    }
    final sortedReasons = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final inSelection = _selectedIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.autoLedgerUnparsedCount(_unparsed.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                key: const Key('auto-ledger-unparsed-dismiss'),
                onPressed: _dismissUnparsed,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(l10n.autoLedgerUnparsedDismiss),
              ),
            ],
          ),
        ),
        // Reason tag filter chips.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  key: const Key('auto-ledger-reason-all'),
                  label: Text(l10n.all),
                  selected: _reasonFilter == null,
                  onSelected: (_) =>
                      setState(() => _reasonFilter = null),
                ),
              ),
              for (final entry in sortedReasons)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    key: Key('auto-ledger-reason-${entry.key}'),
                    label: Text('${entry.key} (${entry.value})'),
                    selected: _reasonFilter == entry.key,
                    onSelected: (_) =>
                        setState(() => _reasonFilter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (final event in _filteredUnparsed.take(20))
          _UnparsedEventTile(
            event: event,
            inSelection: inSelection,
            selected: _selectedIds.contains(event.id),
            onTap: () {
              if (inSelection) {
                setState(() => _toggleSelection(event.id));
              } else {
                _rescueEvent(event);
              }
            },
            onLongPress: () {
              setState(() => _toggleSelection(event.id));
            },
          ),
        if (_filteredUnparsed.isEmpty && _reasonFilter != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                l10n.autoLedgerUnparsedEmpty,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActions(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('auto-ledger-sync-now'),
          onPressed: _syncing ? null : _syncNow,
          icon: _syncing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(l10n.autoLedgerSyncNow),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          ListTile(
            key: const Key('auto-ledger-status'),
            leading: const Icon(Icons.info_outline),
            title: Text(_status!),
          ),
        ],
      ],
    );
  }

  Widget _buildRulesLink(AppLocalizations l10n) {
    return ListTile(
      key: const Key('auto-ledger-rules-link'),
      leading: const Icon(Icons.rule_outlined),
      title: Text(l10n.autoLedgerRulesTitle),
      subtitle: Text(l10n.autoLedgerRulesSubtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_userRuleCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_userRuleCount',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => context.go('/settings/auto-ledger/rules'),
    );
  }

  void _toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
  }

  Future<void> _bulkRescueSelected() async {
    if (_selectedIds.isEmpty) return;
    final picked =
        _unparsed.where((e) => _selectedIds.contains(e.id)).toList();
    if (picked.isEmpty) return;
    final result = await showBulkUnparsedRescueSheet(
      context: context,
      events: picked,
    );
    if (!mounted || result == null) return;

    final service = ref.read(ledgerAppServiceProvider);
    var successCount = 0;
    final failed = <String>{};
    for (final event in picked) {
      try {
        await service.rescueUnparsedEvent(
          direction: 'expense',
          // The user only enters the amount for the bulk sheet, so all
          // rescued transactions in this batch share that amount. The
          // fingerprint (and therefore server dedupe) is per-event though,
          // so mixing this with previously-rescued events is safe.
          amountMinor: result.amountMinor,
          merchant: result.merchant,
          note: result.note,
          occurredAt: event.occurredAt,
          platform: event.platform ?? 'unknown',
          reasonTag: event.reasonTag,
          unparsedEventId: event.id,
          categoryAccountId: result.categoryAccountId,
        );
        await _notifications.dismissUnparsedEvent(event.id);
        successCount += 1;
      } catch (error) {
        // Skip on UNIQUE (already posted elsewhere); record everything
        // else as a failure so the user can investigate.
        if (error.toString().contains('UNIQUE') ||
            error.toString().contains('constraint failed')) {
          await _notifications.dismissUnparsedEvent(event.id);
        } else {
          failed.add(event.id);
        }
      }
    }

    setState(() {
      _unparsed =
          _unparsed.where((e) => !_selectedIds.contains(e.id)).toList();
      _selectedIds.clear();
      if (_reasonFilter != null &&
          !_unparsed.any((e) => e.reasonTag == _reasonFilter)) {
        _reasonFilter = null;
      }
      if (result.learnedRule != null) _userRuleCount += 1;
    });

    if (successCount > 0) {
      invalidateLedgerViews(ref);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final l10n = l10nOf(context);
    if (failed.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.autoLedgerBulkRescueSuccess(successCount)),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.autoLedgerBulkRescuePartial(successCount, failed.length),
          ),
        ),
      );
    }
  }
}

/// Renders a single unparsed event as a ListTile that adapts to either
/// "single-tap to rescue" mode or "checkbox multi-select" mode.
class _UnparsedEventTile extends StatelessWidget {
  const _UnparsedEventTile({
    required this.event,
    required this.inSelection,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final UnparsedPaymentEvent event;
  final bool inSelection;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static String _platformLabel(String? platform) {
    switch (platform) {
      case 'wechat':
        return '微信支付';
      case 'alipay':
        return '支付宝';
      default:
        return platform ?? '未知平台';
    }
  }

  static String _preview(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 80) return flat;
    return '${flat.substring(0, 80)}…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = l10nOf(context);
    return ListTile(
      key: Key('auto-ledger-unparsed-${event.id}'),
      leading: inSelection
          ? Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected ? theme.colorScheme.primary : null,
            )
          : const Icon(Icons.help_outline),
      title: Text(_platformLabel(event.platform)),
      subtitle: Text(
        '${event.reasonTag} · '
        '${event.occurredAt.toLocal().toString().substring(11, 16)}\n'
        '${_preview(event.rawText)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      selected: selected,
      trailing: inSelection
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.autoLedgerUnparsedCopy,
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: event.rawText),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.autoLedgerUnparsedCopied),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: l10n.autoLedgerRescueTitle,
                  icon: const Icon(Icons.edit_note_outlined),
                  onPressed: onTap,
                ),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
