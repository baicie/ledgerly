import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

class ConflictsPage extends ConsumerWidget {
  const ConflictsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final conflicts = ref.watch(conflictsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.conflicts)),
      body: SafeArea(
        top: false,
        child: conflicts.when(
          data: (items) {
            if (items.isEmpty) {
              return _ConflictsEmpty();
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: EdgeInsets.only(
                    top: index == 0 ? 0 : 12,
                  ),
                  child: _ConflictCard(
                    item: item,
                    onResolveRemote: () => _resolve(
                      context,
                      ref,
                      item,
                      ConflictResolution.useRemote,
                    ),
                    onKeepLocal: () => _resolve(
                      context,
                      ref,
                      item,
                      ConflictResolution.keepLocal,
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    SyncConflictItem item,
    ConflictResolution resolution,
  ) async {
    await ref.read(ledgerRepositoryProvider).resolveConflict(
          item.id,
          resolution: resolution,
        );
    ref.invalidate(conflictsProvider);
    ref.invalidate(syncStatusProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(L10n.current.conflictResolved),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

class _ConflictsEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return LedgerlyContent(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
            child: LedgerlySection(
              child: Column(
                children: [
                  const Icon(
                    Icons.task_alt_rounded,
                    size: 48,
                    color: LedgerlyColors.brandMint,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noConflicts,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.item,
    required this.onResolveRemote,
    required this.onKeepLocal,
  });

  final SyncConflictItem item;
  final VoidCallback onResolveRemote;
  final VoidCallback onKeepLocal;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final remoteVersion = item.remoteVersion?.toString() ?? l10n.unknown;
    return LedgerlySection(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: LedgerlyColors.warning,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.conflictEntityHint} · ${item.entityId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.reason,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (item.remoteVersion != null) ...[
            const SizedBox(height: 2),
            Text(
              l10n.conflictRemoteVersion(remoteVersion),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('conflict-resolve-remote'),
                  onPressed: onResolveRemote,
                  icon: const Icon(Icons.cloud_done_outlined, size: 18),
                  label: Text(l10n.useRemote),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('conflict-keep-local'),
                  onPressed: onKeepLocal,
                  icon: const Icon(Icons.replay_outlined, size: 18),
                  label: Text(l10n.keepLocal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.conflictResolveRemoteHint,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
