import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../quick_entry.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.receipt_long), label: '流水'),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet),
      label: '资产',
    ),
    NavigationDestination(icon: Icon(Icons.pie_chart), label: '报表'),
    NavigationDestination(icon: Icon(Icons.settings), label: '我的'),
  ];

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
                      destinations: _railDestinations,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: navigationShell),
                  ],
                )
              : navigationShell,
          floatingActionButton: navigationShell.currentIndex == 0
              ? FloatingActionButton(
                  onPressed: () => openQuickEntry(context),
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: navigationShell.goBranch,
                  destinations: _destinations,
                ),
        ),
      ),
    );
  }
}
