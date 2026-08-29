import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';

const _createBookValue = '__create_book__';

class LedgerlyBookSwitcher extends ConsumerWidget {
  const LedgerlyBookSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final books = ref.watch(booksProvider);
    final selectedBookId = ref.watch(selectedBookIdProvider);

    return books.when(
      skipLoadingOnReload: true,
      loading: () => _label(context, l10n.standardLedger, enabled: false),
      error: (_, __) => _label(context, l10n.standardLedger, enabled: false),
      data: (items) {
        if (items.isEmpty) {
          return _label(context, l10n.standardLedger, enabled: false);
        }
        final selected = items.firstWhere(
          (book) => book.id == selectedBookId,
          orElse: () => items.first,
        );
        final label = localizedLedgerName(l10n, selected.name);
        return PopupMenuButton<String>(
          key: const Key('book-switcher'),
          tooltip: l10n.switchBook,
          padding: EdgeInsets.zero,
          offset: const Offset(0, 8),
          onSelected: (value) => _onSelected(context, ref, value),
          itemBuilder: (context) => [
            for (final book in items)
              PopupMenuItem(
                value: book.id,
                child: _BookMenuRow(
                  label: localizedLedgerName(l10n, book.name),
                  selected: book.id == selected.id,
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _createBookValue,
              child: Row(
                children: [
                  const Icon(Icons.add, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.newBook),
                ],
              ),
            ),
          ],
          child: _label(context, label, enabled: true),
        );
      },
    );
  }

  Widget _label(BuildContext context, String text, {required bool enabled}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (enabled) ...[
          const SizedBox(width: 2),
          const Icon(Icons.expand_more, size: 18, color: LedgerlyColors.muted),
        ],
      ],
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == _createBookValue) {
      final created = await createBookFromDialog(context, ref);
      if (created != null && context.mounted) {
        await ref.read(selectedBookIdProvider.notifier).select(created.id);
      }
      return;
    }
    await ref.read(selectedBookIdProvider.notifier).select(value);
  }
}

class _BookMenuRow extends StatelessWidget {
  const _BookMenuRow({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (selected)
          const Icon(Icons.check, size: 18, color: LedgerlyColors.brand),
      ],
    );
  }
}

Future<Book?> createBookFromDialog(BuildContext context, WidgetRef ref) async {
  final l10n = l10nOf(context);
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.newBook),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: InputDecoration(labelText: l10n.bookName),
        onSubmitted: (_) => Navigator.pop(context, controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(l10n.create),
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
