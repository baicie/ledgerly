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
      body: conflicts.isEmpty
          ? const Center(child: Text('当前无冲突'))
          : ListView.builder(
              itemCount: conflicts.length,
              itemBuilder: (context, index) {
                final c = conflicts[index];
                return ListTile(
                  title: Text(c.entityId),
                  subtitle: Text(c.reason),
                  trailing: TextButton(
                    onPressed: () =>
                        ref.read(conflictsProvider.notifier).keepRemote(c.entityId),
                    child: const Text('保留云端'),
                  ),
                );
              },
            ),
    );
  }
}
