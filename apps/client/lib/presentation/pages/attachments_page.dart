import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_repository.dart';
import '../../data/local_attachment_repository.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

class AttachmentsPage extends ConsumerStatefulWidget {
  const AttachmentsPage({super.key});

  @override
  ConsumerState<AttachmentsPage> createState() => _AttachmentsPageState();
}

class _AttachmentsPageState extends ConsumerState<AttachmentsPage> {
  final _uploadingIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final attachments = ref.watch(localAttachmentsProvider);
    final cloudSync = ref.watch(attachmentCloudSyncProvider);
    final showCloudUpload = !ref.watch(isLocalModeProvider);
    final canUpload = ref.watch(canUploadAttachmentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attachmentsUpload)),
      body: SafeArea(
        top: false,
        child: attachments.when(
          data: (items) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                LedgerlySection(child: Text(l10n.attachmentsLocalHelp)),
                if (cloudSync.hasError) ...[
                  const SizedBox(height: 8),
                  LedgerlySection(
                    child: Text(l10n.attachmentCloudSyncFailure),
                  ),
                ],
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
                      onDelete: () => _delete(item),
                      showCloudUpload: showCloudUpload,
                      canUpload: canUpload,
                      isUploading: _uploadingIds.contains(item.id),
                      onUpload: () => _upload(item),
                    ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
        ),
      ),
    );
  }

  Future<void> _delete(LocalAttachmentRecord item) async {
    try {
      await ref.read(attachmentUploadServiceProvider).deleteAttachment(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nOf(context).attachmentCloudDeleteFailure)),
        );
      }
      return;
    }
    ref.invalidate(localAttachmentsProvider);
    ref.invalidate(attachmentCloudSyncProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(attachmentCloudSyncProvider);
    ref.invalidate(attachmentRetryProvider);
    ref.invalidate(localAttachmentsProvider);
    try {
      await ref.read(attachmentCloudSyncProvider.future);
    } catch (_) {
      // Keep the local list refresh available when cloud sync is offline.
    }
    try {
      await ref.read(attachmentRetryProvider.future);
    } catch (_) {
      // Retry failures remain persisted for the next lifecycle tick.
    }
    await ref.read(localAttachmentsProvider.future);
  }

  Future<void> _upload(LocalAttachmentRecord item) async {
    setState(() => _uploadingIds.add(item.id));
    try {
      await ref.read(attachmentUploadServiceProvider).upload(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nOf(context).attachmentCloudUploadSuccess)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nOf(context).attachmentCloudUploadFailure)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingIds.remove(item.id));
      }
      ref.invalidate(localAttachmentsProvider);
      ref.invalidate(attachmentCloudSyncProvider);
      ref.invalidate(attachmentRetryProvider);
    }
  }
}

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({
    required this.item,
    required this.onDelete,
    this.showCloudUpload = false,
    this.canUpload = false,
    this.isUploading = false,
    this.onUpload,
  });

  final LocalAttachmentRecord item;
  final VoidCallback onDelete;
  final bool showCloudUpload;
  final bool canUpload;
  final bool isUploading;
  final VoidCallback? onUpload;

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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCloudUpload)
            _CloudUploadButton(
              item: item,
              canUpload: canUpload,
              isUploading: isUploading,
              onUpload: onUpload,
            ),
          IconButton(
            tooltip: l10n.deleteTransaction,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _CloudUploadButton extends StatelessWidget {
  const _CloudUploadButton({
    required this.item,
    required this.canUpload,
    required this.isUploading,
    required this.onUpload,
  });

  final LocalAttachmentRecord item;
  final bool canUpload;
  final bool isUploading;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    if (isUploading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (item.cloudUploadStatus == AttachmentCloudStatus.ready) {
      return IconButton(
        tooltip: l10n.attachmentCloudUploaded,
        onPressed: null,
        icon: const Icon(Icons.cloud_done_outlined),
      );
    }
    final failed = item.cloudUploadStatus == AttachmentCloudStatus.failed;
    return IconButton(
      tooltip: !canUpload
          ? l10n.attachmentCloudSignIn
          : failed
              ? l10n.attachmentCloudRetry
              : l10n.attachmentCloudUpload,
      onPressed: canUpload ? onUpload : null,
      icon: Icon(
        failed ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
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
    builder: (context) =>
        _TransactionAttachmentsSheet(transaction: transaction),
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
  final _uploadingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_refreshCloud());
  }

  Future<void> _refreshCloud() async {
    try {
      ref.invalidate(attachmentRetryProvider);
      await ref.read(attachmentCloudSyncProvider.future);
      await ref.read(attachmentRetryProvider.future);
      await _load();
    } catch (_) {
      // The attachments page and pull-to-refresh surface sync errors.
    }
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

  Future<void> _upload(LocalAttachmentRecord item) async {
    setState(() => _uploadingIds.add(item.id));
    try {
      await ref.read(attachmentUploadServiceProvider).upload(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nOf(context).attachmentCloudUploadSuccess)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nOf(context).attachmentCloudUploadFailure)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingIds.remove(item.id));
      }
      ref.invalidate(localAttachmentsProvider);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final showCloudUpload = !ref.watch(isLocalModeProvider);
    final canUpload = ref.watch(canUploadAttachmentsProvider);
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
                showCloudUpload: showCloudUpload,
                canUpload: canUpload,
                isUploading: _uploadingIds.contains(item.id),
                onUpload: () => _upload(item),
                onDelete: () async {
                  try {
                    await ref
                        .read(attachmentUploadServiceProvider)
                        .deleteAttachment(item);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              l10nOf(context).attachmentCloudDeleteFailure),
                        ),
                      );
                    }
                    return;
                  }
                  ref.invalidate(localAttachmentsProvider);
                  ref.invalidate(attachmentCloudSyncProvider);
                  ref.invalidate(attachmentRetryProvider);
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
