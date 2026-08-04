import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';
import '../widgets/ledgerly_summary_card.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider);
    return Scaffold(
      body: SafeArea(
        child: balances.when(
          data: (rows) {
            final assetRows = rows
                .where((row) => row.type == 'asset' || row.type == 'liability')
                .toList();
            final netWorth = assetRows.fold<BigInt>(
              BigInt.zero,
              (total, row) => total + row.balance,
            );
            return LedgerlyContent(
              slivers: [
                SliverToBoxAdapter(
                  child: LedgerlyPageHeader(
                    title: '资产账户',
                    subtitle: '${assetRows.length} 个账户 · 人民币 CNY',
                    actions: [
                      IconButton(
                        tooltip: '新建账户',
                        onPressed: () => _createAccount(context, ref),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  sliver: SliverToBoxAdapter(
                    child: LedgerlySummaryCard(
                      title: '标准账本',
                      balanceLabel: '净资产',
                      balanceMinor: netWorth,
                      incomeMinor: BigInt.zero,
                      expenseMinor: BigInt.zero,
                      showFlow: false,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverToBoxAdapter(
                    child: LedgerlySection(
                      title: '账户明细',
                      trailing: Text(
                        '合计 ${formatDisplayMinor(netWorth)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                      headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                      child: assetRows.isEmpty
                          ? const LedgerlyEmptyState(
                              icon: Icons.account_balance_wallet_outlined,
                              title: '还没有资产账户',
                              message: '新建现金、银行卡或其他资产账户。',
                            )
                          : Column(
                              children: [
                                for (var index = 0;
                                    index < assetRows.length;
                                    index++) ...[
                                  if (index > 0)
                                    const Divider(indent: 70, endIndent: 16),
                                  _AccountTile(row: assetRows[index]),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('账户加载失败：$error')),
        ),
      ),
    );
  }

  Future<void> _createAccount(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(text: '新账户');
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建资产账户'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '账户名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (created == true && name.text.trim().isNotEmpty) {
      await ref.read(ledgerAppServiceProvider).createAccount(
            name: name.text.trim(),
            type: 'asset',
          );
      ref.invalidate(accountBalancesProvider);
    }
    name.dispose();
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.row});

  final AccountBalanceRow row;

  @override
  Widget build(BuildContext context) {
    final color = row.type == 'liability'
        ? LedgerlyColors.income
        : ledgerColorFor(row.name);
    return ListTile(
      minTileHeight: 72,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: LedgerlyIconBadge(
        icon: ledgerIconFor(row.name),
        color: color,
      ),
      title: Text(localizedLedgerName(row.name)),
      subtitle: Text(row.type == 'liability' ? '负债账户' : '资产账户'),
      trailing: Text(
        formatDisplayMinor(row.balance),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: row.balance.isNegative
              ? LedgerlyColors.income
              : LedgerlyColors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
