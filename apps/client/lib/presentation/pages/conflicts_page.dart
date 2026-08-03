import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../providers.dart';

class ConflictsPage extends ConsumerWidget {
  const ConflictsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(conflictsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('冲突处理')),
      body: conflicts.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('当前无冲突'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final c = items[index];
              return ListTile(
                title: Text(c.entityId),
                subtitle: Text(
                  '${c.reason} · 远端版本 ${c.remoteVersion?.toString() ?? '未知'}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await ref.read(ledgerRepositoryProvider).resolveConflict(
                              c.id,
                              resolution: ConflictResolution.useRemote,
                            );
                        ref.invalidate(conflictsProvider);
                        ref.invalidate(syncStatusProvider);
                      },
                      icon: const Icon(Icons.cloud_done_outlined),
                      label: const Text('采用远端'),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(ledgerRepositoryProvider).resolveConflict(
                              c.id,
                              resolution: ConflictResolution.keepLocal,
                            );
                        ref.invalidate(conflictsProvider);
                        ref.invalidate(syncStatusProvider);
                      },
                      icon: const Icon(Icons.replay_outlined),
                      label: const Text('保留本地'),
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
