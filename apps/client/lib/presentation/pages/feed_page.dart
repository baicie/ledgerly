import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('流水')),
      body: txs.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('暂无交易，点击 + 快速记账'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tx = items[index];
              return ListTile(
                title: Text(tx.description ?? '交易'),
                subtitle: Text(tx.occurredAt.toLocal().toString()),
                trailing: Text('${tx.entryCount} 分录'),
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
