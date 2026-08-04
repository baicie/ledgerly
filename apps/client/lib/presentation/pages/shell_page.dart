import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../design/ledgerly_theme.dart';
import '../quick_entry.dart';
import '../widgets/ledgerly_navigation.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: Text('流水'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet),
      label: Text('资产'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: Text('报表'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('我的'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
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
                          tooltip: '记一笔',
                          onPressed: () => openQuickEntry(context),
                          child: const Icon(Icons.add_rounded),
                        ),
                      ),
                      destinations: _railDestinations,
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
