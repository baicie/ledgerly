import 'dart:typed_data';

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
                  _AttachmentTile(
                    item: item,
                    onDelete: () => _delete(ref, item),
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

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({required this.item, required this.onDelete});

  final LocalAttachmentRecord item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return ListTile(
      leading: _AttachmentThumb(path: item.relativePath, mime: item.mime),
      title: Text(item.fileName),
      subtitle: Text(item.mime),
      onTap: item.mime.startsWith('image/')
          ? () => _preview(context, ref, item)
          : null,
      trailing: IconButton(
        tooltip: l10n.deleteTransaction,
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _AttachmentThumb extends ConsumerWidget {
  const _AttachmentThumb({required this.path, required this.mime});

  final String path;
  final String mime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!mime.startsWith('image/')) {
      return const Icon(Icons.attach_file);
    }
    return FutureBuilder<Uint8List?>(
      future: ref.read(attachmentStoreProvider).read(path),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const Icon(Icons.image_outlined);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, width: 40, height: 40, fit: BoxFit.cover),
        );
      },
    );
  }
}

Future<void> _preview(
  BuildContext context,
  WidgetRef ref,
  LocalAttachmentRecord item,
) async {
  final bytes = await ref.read(attachmentStoreProvider).read(item.relativePath);
  if (!context.mounted || bytes == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: InteractiveViewer(
        child: Image.memory(bytes),
      ),
    ),
  );
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
          bookId: ref.read(selectedBookIdProvider),
          transactionId: widget.transaction.id,
        );
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add({required bool imagesOnly}) async {
    setState(() => _busy = true);
    try {
      final picked = await ref.read(userFilePortProvider).pickBinaryFile(
            imagesOnly: imagesOnly,
          );
      if (picked == null) return;
      final store = ref.read(attachmentStoreProvider);
      final repo = ref.read(localAttachmentRepositoryProvider);
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final path = await store.write(id: id, bytes: picked.bytes);
      await repo.insert(
        bookId: ref.read(selectedBookIdProvider),
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
              _AttachmentTile(
                item: item,
                onDelete: () async {
                  await ref
                      .read(attachmentStoreProvider)
                      .delete(item.relativePath);
                  await ref
                      .read(localAttachmentRepositoryProvider)
                      .delete(item.id);
                  ref.invalidate(localAttachmentsProvider);
                  await _load();
                },
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('attachment-add-image'),
                    onPressed: _busy ? null : () => _add(imagesOnly: true),
                    icon: const Icon(Icons.photo_outlined),
                    label: Text(l10n.addImage),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('attachment-add'),
                    onPressed: _busy ? null : () => _add(imagesOnly: false),
                    icon: const Icon(Icons.attach_file),
                    label: Text(l10n.addAttachment),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
