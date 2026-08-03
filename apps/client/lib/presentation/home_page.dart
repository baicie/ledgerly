import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ledgerly')),
      body: txs.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No transactions yet'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final tx = items[index];
              return ListTile(
                title: Text(tx.description ?? 'Transaction'),
                subtitle: Text(
                  '${tx.occurredAt.toLocal()} · ${tx.entryCount} entries',
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addExpense(ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addExpense(WidgetRef ref) async {
    final service = ref.read(ledgerAppServiceProvider);
    await service.createExpense(
      expenseAccountId: 'acc_food',
      fundingAccountId: 'acc_cash',
      amountMinor: BigInt.from(2500),
      description: 'Quick expense',
    );
  }
}
