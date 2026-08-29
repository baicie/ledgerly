import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../quick_entry.dart';
import '../widgets/ledgerly_navigation.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
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
}
