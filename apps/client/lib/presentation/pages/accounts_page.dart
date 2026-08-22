import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/ledgerly_theme.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_finance.dart';
import '../widgets/ledgerly_layout.dart';
import '../widgets/ledgerly_summary_card.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
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
                    title: l10n.assetAccounts,
                    subtitle: l10n.accountsSubtitle(assetRows.length),
                    actions: [
                      IconButton(
                        tooltip: l10n.newAccount,
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
                      title: l10n.standardLedger,
                      balanceLabel: l10n.netWorth,
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
                      title: l10n.accountDetails,
                      trailing: Text(
                        l10n.totalWithAmount(formatDisplayMinor(netWorth)),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                      headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                      child: assetRows.isEmpty
                          ? LedgerlyEmptyState(
                              icon: Icons.account_balance_wallet_outlined,
                              title: l10n.noAssetAccounts,
                              message: l10n.noAssetAccountsHint,
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
          error: (error, _) =>
              Center(child: Text(l10n.accountsLoadFailed('$error'))),
        ),
      ),
    );
  }

  Future<void> _createAccount(BuildContext context, WidgetRef ref) async {
    final l10n = l10nOf(context);
    final name = TextEditingController(text: l10n.newAccountName);
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newAssetAccount),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.accountName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.create),
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
      title: Text(localizedLedgerName(l10nOf(context), row.name)),
      subtitle: Text(
        row.type == 'liability'
            ? l10nOf(context).liabilityAccount
            : l10nOf(context).assetAccount,
      ),
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
