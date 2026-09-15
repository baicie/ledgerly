import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../quick_entry.dart';
import '../widgets/command_palette.dart';
import '../widgets/ledgerly_navigation.dart';

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final railDestinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.receipt_long_outlined),
        selectedIcon: const Icon(Icons.receipt_long),
        label: Text(l10n.navFeed),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: const Icon(Icons.account_balance_wallet),
        label: Text(l10n.navAssets),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.pie_chart_outline),
        selectedIcon: const Icon(Icons.pie_chart),
        label: Text(l10n.navReports),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(l10n.navMe),
      ),
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            openQuickEntry(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            openQuickEntry(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _openCommandPalette(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openCommandPalette(context, ref),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: navigationShell.goBranch,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: LedgerlyColors.surface,
                      leading: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: FloatingActionButton(
                          tooltip: l10n.addTransaction,
                          onPressed: () => openQuickEntry(context),
                          child: const Icon(Icons.add_rounded),
                        ),
                      ),
                      destinations: railDestinations,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: navigationShell),
                  ],
                )
              : navigationShell,
          bottomNavigationBar: wide
              ? null
              : LedgerlyBottomNavigation(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: navigationShell.goBranch,
                  onQuickEntry: () => openQuickEntry(context),
                ),
        ),
      ),
    );
  }

  Future<void> _openCommandPalette(
    BuildContext context,
    WidgetRef ref,
  ) {
    return showCommandPalette(
      context,
      actions: _buildPaletteActions(context, ref),
    );
  }

  List<CommandPaletteAction> _buildPaletteActions(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l10n = l10nOf(context);
    final router = GoRouter.of(context);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final newTxShortcut = isMac ? '⌘N' : 'Ctrl N';

    final actions = <CommandPaletteAction>[
      CommandPaletteAction(
        id: 'action-new',
        icon: Icons.add_circle_outline,
        label: l10n.addTransaction,
        searchTerms: const ['new', 'transaction', '记一笔', '新建'],
        shortcut: newTxShortcut,
        onActivate: () => openQuickEntry(context),
      ),
      CommandPaletteAction(
        id: 'nav-feed',
        icon: Icons.receipt_long_outlined,
        label: l10n.navFeed,
        searchTerms: const ['feed', '流水'],
        onActivate: () => router.go('/feed'),
      ),
      CommandPaletteAction(
        id: 'nav-accounts',
        icon: Icons.account_balance_wallet_outlined,
        label: l10n.navAssets,
        searchTerms: const ['accounts', 'assets', '资产', '账户'],
        onActivate: () => router.go('/accounts'),
      ),
      CommandPaletteAction(
        id: 'nav-reports',
        icon: Icons.pie_chart_outline,
        label: l10n.navReports,
        searchTerms: const ['reports', '报表'],
        onActivate: () => router.go('/reports'),
      ),
      CommandPaletteAction(
        id: 'nav-settings',
        icon: Icons.settings_outlined,
        label: l10n.navMe,
        searchTerms: const ['settings', 'me', '设置', '我的'],
        onActivate: () => router.go('/settings'),
      ),
      CommandPaletteAction(
        id: 'nav-sync',
        icon: Icons.sync,
        label: l10n.syncCenter,
        searchTerms: const ['sync', '同步', 'sync center'],
        onActivate: () => router.go('/settings/sync'),
      ),
      CommandPaletteAction(
        id: 'nav-conflicts',
        icon: Icons.warning_amber_outlined,
        label: l10n.conflicts,
        searchTerms: const ['conflicts', '冲突'],
        onActivate: () => router.go('/settings/conflicts'),
      ),
      CommandPaletteAction(
        id: 'nav-budgets',
        icon: Icons.savings_outlined,
        label: l10n.budgetTargets,
        searchTerms: const ['budgets', '预算'],
        onActivate: () => router.go('/settings/budgets'),
      ),
      CommandPaletteAction(
        id: 'nav-categories',
        icon: Icons.category_outlined,
        label: l10n.categoryManagement,
        searchTerms: const ['categories', '分类'],
        onActivate: () => router.go('/settings/categories'),
      ),
      CommandPaletteAction(
        id: 'nav-recurring',
        icon: Icons.repeat,
        label: l10n.recurring,
        searchTerms: const ['recurring', '周期', '周期记账'],
        onActivate: () => router.go('/settings/recurring'),
      ),
      CommandPaletteAction(
        id: 'nav-export',
        icon: Icons.file_download_outlined,
        label: l10n.exportCsv,
        searchTerms: const ['export', '导出'],
        onActivate: () => router.go('/settings/export'),
      ),
      CommandPaletteAction(
        id: 'nav-import',
        icon: Icons.file_upload_outlined,
        label: l10n.importCsv,
        searchTerms: const ['import', '导入'],
        onActivate: () => router.go('/settings/import'),
      ),
      CommandPaletteAction(
        id: 'nav-attachments',
        icon: Icons.attachment_outlined,
        label: l10n.attachmentsUpload,
        searchTerms: const ['attachments', '附件'],
        onActivate: () => router.go('/settings/attachments'),
      ),
      CommandPaletteAction(
        id: 'nav-auto-ledger',
        icon: Icons.auto_awesome_outlined,
        label: l10n.autoLedgerTitle,
        searchTerms: const ['auto', '自动记账', 'notification'],
        onActivate: () => router.go('/settings/auto-ledger'),
      ),
      CommandPaletteAction(
        id: 'nav-merchant-rules',
        icon: Icons.rule,
        label: l10n.autoLedgerRulesTitle,
        searchTerms: const ['merchant', 'rules', '商户规则'],
        onActivate: () => router.go('/settings/auto-ledger/rules'),
      ),
      CommandPaletteAction(
        id: 'nav-ai',
        icon: Icons.psychology_outlined,
        label: l10n.aiSpendInsights,
        searchTerms: const ['ai', 'assistant', 'AI 助手'],
        onActivate: () => router.go('/settings/ai'),
      ),
      CommandPaletteAction(
        id: 'nav-subscription',
        icon: Icons.star_outline,
        label: l10n.subscription,
        searchTerms: const ['subscription', '订阅', 'plan'],
        onActivate: () => router.go('/settings/subscription'),
      ),
      CommandPaletteAction(
        id: 'nav-fx',
        icon: Icons.currency_exchange,
        label: l10n.fxRates,
        searchTerms: const ['fx', 'rates', '汇率'],
        onActivate: () => router.go('/settings/fx'),
      ),
      CommandPaletteAction(
        id: 'nav-family',
        icon: Icons.group_outlined,
        label: l10n.familySharing,
        searchTerms: const ['family', 'invite', '家庭', '邀请'],
        onActivate: () => router.go('/settings/family'),
      ),
      CommandPaletteAction(
        id: 'nav-keyboard',
        icon: Icons.keyboard_outlined,
        label: l10n.keyboardShortcutsTitle,
        searchTerms: const ['keyboard', 'shortcuts', '键盘', '快捷键'],
        onActivate: () => router.go('/settings/keyboard'),
      ),
    ];

    // Only expose "Sync Now" in connected (non-local) mode.
    final hasEndpoint = ref.read(apiEndpointProvider) != null;
    if (hasEndpoint) {
      actions.add(
        CommandPaletteAction(
          id: 'action-sync',
          icon: Icons.sync,
          label: l10n.syncNow,
          searchTerms: const ['sync now', '立即同步', 'pull', 'push'],
          onActivate: () {
            final sync = ref.read(syncServiceProvider);
            // Fire-and-forget: snackbar feedback is handled by SyncCenter.
            unawaited(sync.syncNow());
          },
        ),
      );
    }
    return actions;
  }
}