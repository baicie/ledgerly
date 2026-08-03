import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _createAccount(context, ref),
          ),
        ],
      ),
      body: balances.when(
        data: (rows) => ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return ListTile(
              title: Text(row.name),
              subtitle: Text(row.type),
              trailing: Text(formatMinor(row.balance)),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Future<void> _createAccount(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(text: '新账户');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建资产账户'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(ledgerAppServiceProvider).createAccount(
            name: name.text,
            type: 'asset',
          );
      ref.invalidate(accountBalancesProvider);
    }
  }
}
