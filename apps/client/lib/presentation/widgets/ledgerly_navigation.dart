import 'package:flutter/material.dart';

import '../design/ledgerly_theme.dart';

class LedgerlyBottomNavigation extends StatelessWidget {
  const LedgerlyBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onQuickEntry,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickEntry;

  static const _destinations = [
    _Destination(Icons.receipt_long_outlined, Icons.receipt_long, '流水'),
    _Destination(
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      '资产',
    ),
    _Destination(Icons.analytics_outlined, Icons.analytics, '报表'),
    _Destination(Icons.settings_outlined, Icons.settings, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 76 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            top: 12,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: LedgerlyColors.surface,
                border: Border(
                  top: BorderSide(color: LedgerlyColors.divider),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    _item(context, 0),
                    _item(context, 1),
                    const SizedBox(width: 72),
                    _item(context, 2),
                    _item(context, 3),
                  ],
                ),
              ),
            ),
          ),
          Tooltip(
            message: '记一笔',
            child: Semantics(
              button: true,
              label: '记一笔',
              child: Material(
                color: LedgerlyColors.action,
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onQuickEntry,
                  child: const SizedBox.square(
                    dimension: 62,
                    child: Icon(Icons.add_rounded, size: 34),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int index) {
    final destination = _destinations[index];
    final selected = selectedIndex == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => onDestinationSelected(index),
          child: SizedBox(
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 24,
                  color: selected ? LedgerlyColors.brand : LedgerlyColors.muted,
                ),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected
                            ? LedgerlyColors.brand
                            : LedgerlyColors.muted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
