import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';

class ConflictsPage extends ConsumerWidget {
  const ConflictsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final conflicts = ref.watch(conflictsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.conflicts)),
      body: conflicts.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noConflicts));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final c = items[index];
              return ListTile(
                title: Text(c.entityId),
                subtitle: Text(
                  l10n.conflictSubtitle(
                    c.reason,
                    c.remoteVersion?.toString() ?? l10n.unknown,
                  ),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await ref
                            .read(ledgerRepositoryProvider)
                            .resolveConflict(
                              c.id,
                              resolution: ConflictResolution.useRemote,
                            );
                        ref.invalidate(conflictsProvider);
                        ref.invalidate(syncStatusProvider);
                      },
                      icon: const Icon(Icons.cloud_done_outlined),
                      label: Text(l10n.useRemote),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref
                            .read(ledgerRepositoryProvider)
                            .resolveConflict(
                              c.id,
                              resolution: ConflictResolution.keepLocal,
                            );
                        ref.invalidate(conflictsProvider);
                        ref.invalidate(syncStatusProvider);
                      },
                      icon: const Icon(Icons.replay_outlined),
                      label: Text(l10n.keepLocal),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
