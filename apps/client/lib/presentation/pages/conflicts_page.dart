import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                subtitle: Text(c.reason),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(ledgerRepositoryProvider)
                        .resolveConflict(c.id);
                    ref.invalidate(conflictsProvider);
                  },
                  child: const Text('确认'),
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
