import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

class SyncCenterPage extends ConsumerStatefulWidget {
  const SyncCenterPage({super.key});

  @override
  ConsumerState<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends ConsumerState<SyncCenterPage> {
  var _busy = false;

  Future<void> _runSync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sync = ref.read(syncServiceProvider);
      final result = await sync.syncNow();
      ref.invalidate(syncStatusProvider);
      ref.invalidate(transactionListProvider);
      ref.invalidate(categoryAccountsProvider('expense'));
      ref.invalidate(categoryAccountsProvider('income'));
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(conflictsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.ok
                  ? l10nOf(context).syncSuccess(result.cursor)
                  : l10nOf(context).syncFailed(result.message),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final status = ref.watch(syncStatusProvider);
    final isLocal = ref.watch(apiEndpointProvider) == null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncCenter)),
      body: SafeArea(
        top: false,
        child: status.when(
          data: (s) => LedgerlyContent(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: _StatusHeader(
                    status: s,
                    isLocal: isLocal,
                    busy: _busy,
                    onSync: isLocal ? null : _runSync,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: LedgerlySection(
                    title: l10n.syncCursorLabel,
                    child: _KeyValueRow(
                      icon: Icons.history_rounded,
                      text: '${s.cursor}',
                    ),
                  ),
                ),
              ),
              if (s.remoteBookId != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  sliver: SliverToBoxAdapter(
                    child: LedgerlySection(
                      title: l10n.syncRemoteBook,
                      child: _KeyValueRow(
                        icon: Icons.book_outlined,
                        text: s.remoteBookId!,
                        selectable: true,
                      ),
                    ),
                  ),
                ),
              if (s.lastError != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  sliver: SliverToBoxAdapter(
                    child: _ErrorCard(message: s.lastError!),
                  ),
                ),
              if (isLocal)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  sliver: SliverToBoxAdapter(
                    child: _LocalOnlyBanner(message: l10n.localOnlyHelp),
                  ),
                ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.status,
    required this.isLocal,
    required this.busy,
    required this.onSync,
  });

  final SyncStatusView status;
  final bool isLocal;
  final bool busy;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final hasError = status.lastError != null;
    final tone = isLocal
        ? _StatusTone.neutral
        : hasError
            ? _StatusTone.error
            : _StatusTone.ok;
    final label = isLocal
        ? l10n.localOnlyStorage
        : busy
            ? l10n.syncStatusPending
            : hasError
                ? l10n.syncStatusError
                : l10n.syncStatusReady;
    return LedgerlySection(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          _StatusDot(tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  l10n.syncPendingCount(status.pendingCount),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (!isLocal)
            busy
                ? const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.icon(
                    onPressed: onSync,
                    icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                    label: Text(l10n.syncNow),
                  ),
        ],
      ),
    );
  }
}

enum _StatusTone { ok, error, neutral }

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.tone});

  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.ok => LedgerlyColors.brandMint,
      _StatusTone.error => LedgerlyColors.income,
      _StatusTone.neutral => LedgerlyColors.disabled,
    };
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.icon,
    required this.text,
    this.selectable = false,
  });

  final IconData icon;
  final String text;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: LedgerlyColors.ink,
        );
    final value = selectable
        ? SelectableText(text, style: valueStyle)
        : Text(text, style: valueStyle);
    return Row(
      children: [
        Icon(icon, size: 18, color: LedgerlyColors.muted),
        const SizedBox(width: 8),
        Expanded(child: value),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return LedgerlySection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: LedgerlyColors.income,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.syncLastError,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: LedgerlyColors.income,
                      ),
                ),
                const SizedBox(height: 4),
                SelectableText(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOnlyBanner extends StatelessWidget {
  const _LocalOnlyBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return LedgerlySection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            color: LedgerlyColors.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
