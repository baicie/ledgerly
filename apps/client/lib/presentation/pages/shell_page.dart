import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';
import '../quick_entry.dart';
import '../widgets/ledgerly_navigation.dart';

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final books = ref.watch(booksProvider);
    final selectedBookId = ref.watch(selectedBookIdProvider);
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

    final bookSwitcher = _BookSwitcher(
      books: books,
      selectedBookId: selectedBookId,
      onSelected: (id) =>
          ref.read(selectedBookIdProvider.notifier).select(id),
      onCreated: () async {
        final created = await _createBook(context, ref);
        if (created != null && context.mounted) {
          await ref.read(selectedBookIdProvider.notifier).select(created.id);
        }
      },
    );

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
                    SizedBox(
                      width: 228,
                      child: Column(
                        children: [
                          bookSwitcher,
                          Expanded(
                            child: NavigationRail(
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
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: navigationShell),
                  ],
                )
              : Column(
                  children: [
                    bookSwitcher,
                    Expanded(child: navigationShell),
                  ],
                ),
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

class _BookSwitcher extends StatelessWidget {
  const _BookSwitcher({
    required this.books,
    required this.selectedBookId,
    required this.onSelected,
    required this.onCreated,
  });

  final AsyncValue<List<Book>> books;
  final String selectedBookId;
  final ValueChanged<String> onSelected;
  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context) {
    return books.when(
      loading: () => const SizedBox(height: 84),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final selected = items.firstWhere(
          (book) => book.id == selectedBookId,
          orElse: () => items.first,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selected.id,
                    icon: const Icon(Icons.expand_more),
                    onChanged: (id) {
                      if (id != null) onSelected(id);
                    },
                    items: [
                      for (final book in items)
                        DropdownMenuItem(
                          value: book.id,
                          child: Text(
                            book.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '新建账本',
                onPressed: onCreated,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<Book?> _createBook(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('新建账本'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: '账本名称'),
        onSubmitted: (_) => Navigator.pop(context, controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.trim().isEmpty) return null;
  final book = await ref.read(ledgerRepositoryProvider).createBook(name: name);
  ref.invalidate(booksProvider);
  ref.invalidate(transactionListProvider);
  invalidateLedgerViews(ref);
  ref.invalidate(selectedBookProvider);
  return book;
}
