import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class SyncCenterPage extends ConsumerWidget {
  const SyncCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('同步中心')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('状态：${status.label}'),
            Text('游标：${status.cursor}'),
            Text('待推送：${status.pendingCount}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(syncStatusProvider.notifier).markSynced(),
              child: const Text('模拟同步完成'),
            ),
            const SizedBox(height: 8),
            const Text(
              '权威数据仍来自 Pull；此页仅展示同步可感知状态。',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
