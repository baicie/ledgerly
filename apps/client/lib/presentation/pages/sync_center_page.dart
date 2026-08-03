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
      body: status.when(
        data: (s) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('状态：${s.label}'),
              Text('游标：${s.cursor}'),
              Text('待推送：${s.pendingCount}'),
              if (s.remoteBookId != null) Text('远端账本：${s.remoteBookId}'),
              if (s.lastError != null) Text('错误：${s.lastError}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final sync = ref.read(syncServiceProvider);
                  final result = await sync.syncNow();
                  ref.invalidate(syncStatusProvider);
                  ref.invalidate(transactionListProvider);
                  ref.invalidate(conflictsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.ok
                              ? '同步成功 cursor=${result.cursor}'
                              : '同步失败：${result.message}',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('立即同步'),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
