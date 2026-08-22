import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../../data/local_attachment_repository.dart';
import '../../domain/ids.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

class AttachmentsPage extends ConsumerWidget {
  const AttachmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final attachments = ref.watch(localAttachmentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attachmentsUpload)),
      body: SafeArea(
        top: false,
        child: attachments.when(
          data: (items) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LedgerlySection(child: Text(l10n.attachmentsLocalHelp)),
              const SizedBox(height: 12),
              if (items.isEmpty)
                LedgerlyEmptyState(
                  icon: Icons.attachment_outlined,
                  title: l10n.noAttachments,
                  message: l10n.attachmentsLocalHelp,
                )
              else
                for (final item in items)
                  ListTile(
                    leading: const Icon(Icons.attach_file),
                    title: Text(item.fileName),
                    subtitle: Text(item.mime),
                    trailing: IconButton(
                      tooltip: l10n.deleteTransaction,
                      onPressed: () => _delete(ref, item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
        ),
      ),
    );
  }

  Future<void> _delete(WidgetRef ref, LocalAttachmentRecord item) async {
    await ref.read(attachmentStoreProvider).delete(item.relativePath);
    await ref.read(localAttachmentRepositoryProvider).delete(item.id);
    ref.invalidate(localAttachmentsProvider);
  }
}

Future<void> showTransactionAttachmentsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required TransactionSummary transaction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _TransactionAttachmentsSheet(transaction: transaction),
  );
}

class _TransactionAttachmentsSheet extends ConsumerStatefulWidget {
  const _TransactionAttachmentsSheet({required this.transaction});

  final TransactionSummary transaction;

  @override
  ConsumerState<_TransactionAttachmentsSheet> createState() =>
      _TransactionAttachmentsSheetState();
}

class _TransactionAttachmentsSheetState
    extends ConsumerState<_TransactionAttachmentsSheet> {
  List<LocalAttachmentRecord> _items = const [];
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ref.read(localAttachmentRepositoryProvider).list(
          bookId: defaultBookId,
          transactionId: widget.transaction.id,
        );
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      final picked = await ref.read(userFilePortProvider).pickBinaryFile();
      if (picked == null) return;
      final store = ref.read(attachmentStoreProvider);
      final repo = ref.read(localAttachmentRepositoryProvider);
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final path = await store.write(id: id, bytes: picked.bytes);
      await repo.insert(
        bookId: defaultBookId,
        transactionId: widget.transaction.id,
        fileName: picked.name,
        mime: picked.mime,
        relativePath: path,
      );
      ref.invalidate(localAttachmentsProvider);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.transaction.description?.trim().isNotEmpty == true
                  ? widget.transaction.description!
                  : localizedLedgerName(l10n, widget.transaction.categoryName),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty) Text(l10n.noAttachments),
            for (final item in _items)
              ListTile(
                title: Text(item.fileName),
                trailing: IconButton(
                  onPressed: () async {
                    await ref
                        .read(attachmentStoreProvider)
                        .delete(item.relativePath);
                    await ref
                        .read(localAttachmentRepositoryProvider)
                        .delete(item.id);
                    ref.invalidate(localAttachmentsProvider);
                    await _load();
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            FilledButton.icon(
              key: const Key('attachment-add'),
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.attach_file),
              label: Text(l10n.addAttachment),
            ),
          ],
        ),
      ),
    );
  }
}
