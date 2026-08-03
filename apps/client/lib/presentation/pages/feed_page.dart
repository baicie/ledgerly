import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final txs = ref.watch(monthTransactionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('流水'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).state =
                  DateTime(month.year, month.month - 1);
            },
          ),
          Center(child: Text('${month.year}-${month.month.toString().padLeft(2, '0')}')),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).state =
                  DateTime(month.year, month.month + 1);
            },
          ),
        ],
      ),
      body: txs.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('本月暂无交易，点击 + 快速记账'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tx = items[index];
              return ListTile(
                title: Text(tx.description ?? '交易'),
                subtitle: Text(tx.occurredAt.toLocal().toString()),
                onTap: () => context.go('/feed/revisions/${tx.id}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref
                        .read(ledgerAppServiceProvider)
                        .deleteTransaction(tx.id);
                    ref.invalidate(monthTransactionsProvider);
                    ref.invalidate(transactionListProvider);
                    ref.invalidate(accountBalancesProvider);
                  },
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
