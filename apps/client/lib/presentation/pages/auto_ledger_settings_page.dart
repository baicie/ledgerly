import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auto_ledger_service.dart';
import '../../l10n/l10n.dart';
import '../../services/payment_notification_service.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

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
  final _notifications = PaymentNotificationService();

  bool? _granted;
  List<PendingPaymentEvent> _pending = const [];
  bool _loading = true;
  bool _syncing = false;
  String? _status;
  String? _error;

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
      if (!mounted) return;
      setState(() {
        _granted = granted;
        _pending = pending;
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

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.autoLedgerTitle)),
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
                  child: _buildActions(l10n),
                ),
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
}
