import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../quick_entry.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButton: navigationShell.currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => openQuickEntry(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: '流水'),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet),
            label: '资产',
          ),
          NavigationDestination(icon: Icon(Icons.pie_chart), label: '报表'),
          NavigationDestination(icon: Icon(Icons.settings), label: '我的'),
        ],
      ),
    );
  }
}
