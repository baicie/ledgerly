import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup_encryption.dart';
import '../../application/backup_metadata_store.dart';
import '../../application/backup_schedule.dart';
import '../../application/backup_service.dart';
import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

/// Three-button console that lets the user export a full snapshot of
/// the device, restore from a backup file, or wipe everything.
///
/// The page intentionally never holds the on-disk bytes — it delegates
/// file I/O to [BackupService] / [BackupFilePort] so tests can swap in
/// the in-memory port without touching the real filesystem.
class DataGovernancePage extends ConsumerStatefulWidget {
  const DataGovernancePage({super.key});

  @override
  ConsumerState<DataGovernancePage> createState() => _DataGovernancePageState();
}

class _DataGovernancePageState extends ConsumerState<DataGovernancePage> {
  /// `null` when nothing has happened yet; otherwise carries the last
  /// destination path so the user can find / share the file again.
  String? _lastBackupPath;

  /// When the user picks a file and asks for a preview, hold the parsed
  /// document so the confirm dialog can call [BackupService.restore].
  BackupDocument? _pendingDocument;

  /// Subset of books the next export should cover. Empty set means
  /// "every book" — the default Phase 6 behaviour.
  final Set<String> _selectedBookIds = <String>{};

  /// Phase 10: optional password wrapping. When true the export button
  /// writes a v3 `.enc.zip` and the password fields are visible.
  bool _encryptBackup = false;
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  /// True when [_pendingDocument] came from a plaintext v1/v2 file so
  /// the restore preview can nudge the user toward encrypted backups.
  bool _pendingIsUnencrypted = false;

  bool _busy = false;
  String? _error;

  BackupService get _service => ref.read(backupServiceProvider);

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() {
      _busy = value;
      if (value) _error = null;
    });
  }

  String? get _exportPassword {
    if (!_encryptBackup) return null;
    return _passwordController.text;
  }

  bool get _exportPasswordReady {
    if (!_encryptBackup) return true;
    final password = _passwordController.text;
    if (password.length < 8) return false;
    return password == _passwordConfirmController.text;
  }

  void _syncExportPasswordProvider() {
    ref.read(encryptedBackupPasswordProvider.notifier).state = _exportPassword;
  }

  Future<void> _setAutoBackupEnabled(bool enabled) async {
    final store = ref.read(backupScheduleStoreProvider);
    final current = await store.read();
    final next = current.copyWith(enabled: enabled);
    await store.save(next);
    ref.invalidate(backupScheduleProvider);
    if (enabled) await _runAutoBackupTick();
  }

  Future<void> _setAutoBackupInterval(int intervalDays) async {
    final store = ref.read(backupScheduleStoreProvider);
    final current = await store.read();
    final next = current.copyWith(intervalDays: intervalDays);
    await store.save(next);
    ref.invalidate(backupScheduleProvider);
    if (next.enabled) await _runAutoBackupTick();
  }

  /// User-initiated check from the data-governance page. Silent launch
  /// ticks live in [autoBackupTickProvider]; this path also refreshes
  /// the shareable last-path so the status card and share button update.
  Future<void> _runAutoBackupTick() async {
    _setBusy(true);
    try {
      final result = await ref.read(autoBackupCoordinatorProvider).tick();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (result.ran) _lastBackupPath = result.path;
      });
      if (result.ran) ref.invalidate(backupMetadataProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  // -- Export -----------------------------------------------------------

  /// Trigger an export. When [bookIds] is non-empty the service limits
  /// the snapshot to those books; otherwise it falls back to the
  /// "every book" default. We always re-read the persisted metadata so
  /// the status card + stale banner refresh after a successful export.
  Future<void> _exportBackup({Set<String>? bookIds}) async {
    final l10n = l10nOf(context);
    if (!_exportPasswordReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _passwordController.text.length < 8
                ? l10n.dataGovernancePasswordTooShort
                : l10n.dataGovernancePasswordMismatch,
          ),
        ),
      );
      return;
    }
    final filter = (bookIds != null && bookIds.isNotEmpty)
        ? Set<String>.unmodifiable(bookIds)
        : null;
    final password = _exportPassword;
    _setBusy(true);
    try {
      final path = await _service.exportToFile(
        bookIds: filter,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _lastBackupPath = path;
        _busy = false;
      });
      _passwordController.clear();
      _passwordConfirmController.clear();
      ref.read(encryptedBackupPasswordProvider.notifier).state = null;
      // Re-read the persisted metadata so the status card + stale
      // banner refresh immediately after a successful export.
      ref.invalidate(backupMetadataProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dataGovernanceBackupSuccess(path))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceBackupFailed('$error')),
        ),
      );
    }
  }

  void _toggleBookSelection(String bookId) {
    setState(() {
      if (_selectedBookIds.contains(bookId)) {
        _selectedBookIds.remove(bookId);
      } else {
        _selectedBookIds.add(bookId);
      }
    });
  }

  Future<void> _shareBackup(String path) async {
    final l10n = l10nOf(context);
    try {
      await _service.shareFile(path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceBackupFailed('$error')),
        ),
      );
    }
  }

  // -- Restore ----------------------------------------------------------

  Future<void> _pickRestoreFile() async {
    final l10n = l10nOf(context);
    _setBusy(true);
    try {
      var document = await _service.pickAndRead();
      if (!mounted) return;
      if (document == null) {
        setState(() => _busy = false);
        return;
      }
      final wasEncrypted = document.isEncrypted;
      if (wasEncrypted) {
        setState(() => _busy = false);
        final unlocked = await _unlockEncryptedDocument(document);
        if (!mounted) return;
        if (unlocked == null) return;
        document = unlocked;
      }
      setState(() {
        _pendingDocument = document;
        _pendingIsUnencrypted = !wasEncrypted;
        _busy = false;
      });
    } on BackupFormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceImportFailed(error.message)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceImportFailed('$error')),
        ),
      );
    }
  }

  Future<BackupDocument?> _unlockEncryptedDocument(
    BackupDocument document,
  ) {
    final l10n = l10nOf(context);
    return showDialog<BackupDocument>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _UnlockDialog(
        l10n: l10n,
        onUnlock: (password) => _service.unlockEncrypted(
          document,
          password: password,
        ),
      ),
    );
  }

  void _cancelRestore() {
    setState(() {
      _pendingDocument = null;
      _pendingIsUnencrypted = false;
    });
  }

  Future<void> _confirmRestore() async {
    final l10n = l10nOf(context);
    final document = _pendingDocument;
    if (document == null) return;

    final confirmed = await showDialogDialog<bool>(
      context: context,
      builder: (dialogContext) => _RestoreConfirmDialog(
        summary: document.summary,
        l10n: l10n,
      ),
    );
    if (confirmed != true || !mounted) return;

    _setBusy(true);
    String safetyPath;
    try {
      safetyPath = await _service.writeSafetyBackup();
      await _service.restore(document);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceRestoreFailed('$error')),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _pendingDocument = null;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dataGovernanceRestoreSuccess)),
    );
    // Surface the safety path so the user can recover manually if
    // something looks off after the restore finishes.
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('data-governance-safety-path'),
        content: Text('Safety: $safetyPath'),
        duration: const Duration(seconds: 6),
      ),
    );
    invalidateLedgerViews(ref);
  }

  // -- Wipe -------------------------------------------------------------

  Future<void> _confirmWipe() async {
    final l10n = l10nOf(context);
    final confirmed = await showDialogDialog<bool>(
      context: context,
      builder: (dialogContext) => _WipeConfirmDialog(l10n: l10n),
    );
    if (confirmed != true || !mounted) return;

    _setBusy(true);
    try {
      await _service.wipeLocalData();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceWipeFailed('$error')),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dataGovernanceWipeSuccess)),
    );
    ref.invalidate(backupMetadataProvider);
    invalidateLedgerViews(ref);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final metadataAsync = ref.watch(backupMetadataProvider);
    final metadata = metadataAsync.maybeWhen(
      data: (value) => value,
      orElse: () => BackupMetadata.empty,
    );
    final schedule = ref.watch(backupScheduleProvider).maybeWhen(
          skipLoadingOnReload: true,
          data: (value) => value,
          orElse: () => BackupSchedule.disabled,
        );
    final booksAsync = ref.watch(booksProvider);
    final availableBooks = booksAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <Book>[],
    );
    final now = DateTime.now();
    final staleAgeDays = metadata.lastBackupAt == null
        ? null
        : now.difference(metadata.lastBackupAt!.toLocal()).inDays;
    final isStale =
        staleAgeDays == null ? false : staleAgeDays >= kBackupStaleDays;
    final showStaleBanner = isStale && !_busy;
    final exportSelection = _selectedBookIds.isEmpty
        ? null
        : Set<String>.unmodifiable(_selectedBookIds);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataGovernanceTitle)),
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            SliverToBoxAdapter(
              child: LedgerlyPageHeader(
                title: l10n.dataGovernanceTitle,
                subtitle: l10n.dataGovernanceSubtitle,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: _BackupStatusCard(
                  l10n: l10n,
                  metadata: metadata,
                  now: now,
                ),
              ),
            ),
            if (showStaleBanner)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                sliver: SliverToBoxAdapter(
                  child: _StaleBanner(
                    l10n: l10n,
                    days: staleAgeDays,
                    onAction: _busy
                        ? null
                        : () => _exportBackup(bookIds: exportSelection),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverToBoxAdapter(
                child: _BackupSection(
                  l10n: l10n,
                  busy: _busy,
                  availableBooks: availableBooks,
                  selectedBookIds: _selectedBookIds,
                  lastBackupPath: _lastBackupPath,
                  pendingSummary: _pendingDocument?.summary,
                  pendingIsUnencrypted: _pendingIsUnencrypted,
                  pendingSchemaVersion: _pendingDocument?.schemaVersion,
                  encryptBackup: _encryptBackup,
                  passwordController: _passwordController,
                  passwordConfirmController: _passwordConfirmController,
                  autoBackupEnabled: schedule.enabled,
                  autoBackupIntervalDays: schedule.intervalDays,
                  onAutoBackupChanged: _busy
                      ? null
                      : (enabled) => unawaited(_setAutoBackupEnabled(enabled)),
                  onAutoBackupIntervalChanged: _busy
                      ? null
                      : (days) => unawaited(_setAutoBackupInterval(days)),
                  onEncryptChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _encryptBackup = value);
                          _syncExportPasswordProvider();
                        },
                  onPasswordChanged: (_) {
                    setState(() {});
                    _syncExportPasswordProvider();
                  },
                  onExport: _busy || !_exportPasswordReady
                      ? null
                      : () => _exportBackup(bookIds: exportSelection),
                  onToggleBook: _busy ? null : _toggleBookSelection,
                  onShare: _busy || _lastBackupPath == null
                      ? null
                      : () => _shareBackup(_lastBackupPath!),
                  onPickRestore: _busy ? null : _pickRestoreFile,
                  onCancelRestore:
                      _busy || _pendingDocument == null ? null : _cancelRestore,
                  onConfirmRestore: _busy || _pendingDocument == null
                      ? null
                      : _confirmRestore,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: _DangerSection(
                  l10n: l10n,
                  busy: _busy,
                  onWipe: _busy ? null : _confirmWipe,
                ),
              ),
            ),
            if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection({
    required this.l10n,
    required this.busy,
    required this.availableBooks,
    required this.selectedBookIds,
    required this.lastBackupPath,
    required this.pendingSummary,
    required this.pendingIsUnencrypted,
    required this.pendingSchemaVersion,
    required this.encryptBackup,
    required this.passwordController,
    required this.passwordConfirmController,
    required this.autoBackupEnabled,
    required this.autoBackupIntervalDays,
    required this.onAutoBackupChanged,
    required this.onAutoBackupIntervalChanged,
    required this.onEncryptChanged,
    required this.onPasswordChanged,
    required this.onExport,
    required this.onToggleBook,
    required this.onShare,
    required this.onPickRestore,
    required this.onCancelRestore,
    required this.onConfirmRestore,
  });

  final AppLocalizations l10n;
  final bool busy;
  final List<Book> availableBooks;
  final Set<String> selectedBookIds;
  final String? lastBackupPath;
  final BackupSummary? pendingSummary;
  final bool pendingIsUnencrypted;
  final int? pendingSchemaVersion;
  final bool encryptBackup;
  final TextEditingController passwordController;
  final TextEditingController passwordConfirmController;
  final bool autoBackupEnabled;
  final int autoBackupIntervalDays;
  final ValueChanged<bool>? onAutoBackupChanged;
  final ValueChanged<int>? onAutoBackupIntervalChanged;
  final ValueChanged<bool>? onEncryptChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback? onExport;
  final ValueChanged<String>? onToggleBook;
  final VoidCallback? onShare;
  final VoidCallback? onPickRestore;
  final VoidCallback? onCancelRestore;
  final VoidCallback? onConfirmRestore;

  String _exportLabel(int totalBooks) {
    if (encryptBackup) {
      if (selectedBookIds.isEmpty) {
        return l10n.dataGovernanceExportEncryptedAll(totalBooks);
      }
      return l10n.dataGovernanceExportEncryptedSelected(selectedBookIds.length);
    }
    if (selectedBookIds.isEmpty) {
      return l10n.dataGovernanceExportAll(totalBooks);
    }
    return l10n.dataGovernanceExportSelected(selectedBookIds.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMultipleBooks = availableBooks.length > 1;
    final exportLabel = _exportLabel(availableBooks.length);
    return LedgerlySection(
      title: l10n.dataGovernanceSectionBackup,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -- Export ---------------------------------------------------
          ListTile(
            key: const Key('data-governance-export'),
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(l10n.dataGovernanceBackup),
            subtitle: Text(l10n.dataGovernanceBackupSubtitle),
          ),
          if (hasMultipleBooks)
            _BookSelector(
              l10n: l10n,
              availableBooks: availableBooks,
              selectedBookIds: selectedBookIds,
              onToggle: onToggleBook,
            ),
          CheckboxListTile(
            key: const Key('data-governance-encrypt-checkbox'),
            value: encryptBackup,
            onChanged: onEncryptChanged == null
                ? null
                : (value) => onEncryptChanged!(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.dataGovernanceEncryptWithPassword),
            subtitle: Text(l10n.dataGovernancePasswordHint),
          ),
          if (encryptBackup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('data-governance-encrypt-password'),
                    controller: passwordController,
                    obscureText: true,
                    enabled: !busy,
                    onChanged: onPasswordChanged,
                    decoration: InputDecoration(
                      labelText: l10n.dataGovernanceUnlockPrompt,
                      border: const OutlineInputBorder(),
                      errorText: passwordController.text.isNotEmpty &&
                              passwordController.text.length < 8
                          ? l10n.dataGovernancePasswordTooShort
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('data-governance-encrypt-password-confirm'),
                    controller: passwordConfirmController,
                    obscureText: true,
                    enabled: !busy,
                    onChanged: onPasswordChanged,
                    decoration: InputDecoration(
                      labelText: l10n.dataGovernancePasswordConfirmHint,
                      border: const OutlineInputBorder(),
                      errorText: passwordConfirmController.text.isNotEmpty &&
                              passwordConfirmController.text !=
                                  passwordController.text
                          ? l10n.dataGovernancePasswordMismatch
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.dataGovernanceEncryptLostPasswordWarning,
                    key: const Key('data-governance-encrypt-warning'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            key: const Key('data-governance-auto-backup-switch'),
            value: autoBackupEnabled,
            onChanged: onAutoBackupChanged,
            title: Text(l10n.dataGovernanceAutoBackup),
            subtitle: Text(l10n.dataGovernanceAutoBackupSubtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in kBackupAutoIntervalDays)
                  FilterChip(
                    key: Key('data-governance-auto-interval-$days'),
                    label: Text(l10n.dataGovernanceAutoIntervalDays(days)),
                    selected: autoBackupIntervalDays == days,
                    onSelected: onAutoBackupIntervalChanged == null
                        ? null
                        : (_) => onAutoBackupIntervalChanged!(days),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              l10n.dataGovernanceAutoBackupWarning,
              key: const Key('data-governance-auto-backup-warning'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('data-governance-export-action'),
                  onPressed: onExport,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_alt_outlined),
                  label: Text(
                    busy ? l10n.dataGovernanceBackupInProgress : exportLabel,
                  ),
                ),
                if (lastBackupPath != null)
                  OutlinedButton.icon(
                    key: const Key('data-governance-export-share'),
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share_outlined),
                    label: Text(l10n.dataGovernanceBackupShare),
                  ),
              ],
            ),
          ),
          if (lastBackupPath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                lastBackupPath!,
                key: const Key('data-governance-export-path'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const Divider(indent: 16, endIndent: 16),
          // -- Restore --------------------------------------------------
          ListTile(
            key: const Key('data-governance-restore'),
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(l10n.dataGovernanceRestore),
            subtitle: Text(l10n.dataGovernanceRestoreSubtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('data-governance-restore-pick'),
                  onPressed: onPickRestore,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(l10n.dataGovernanceRestoreAction),
                ),
              ],
            ),
          ),
          if (pendingSummary != null)
            _RestorePreviewCard(
              l10n: l10n,
              summary: pendingSummary!,
              isUnencrypted: pendingIsUnencrypted,
              schemaVersion: pendingSchemaVersion ?? kBackupSchemaVersion,
              onCancel: onCancelRestore,
              onConfirm: onConfirmRestore,
              busy: busy,
            ),
        ],
      ),
    );
  }
}

class _RestorePreviewCard extends StatelessWidget {
  const _RestorePreviewCard({
    required this.l10n,
    required this.summary,
    required this.isUnencrypted,
    required this.schemaVersion,
    required this.onCancel,
    required this.onConfirm,
    required this.busy,
  });

  final AppLocalizations l10n;
  final BackupSummary summary;
  final bool isUnencrypted;
  final int schemaVersion;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = summary.total == 0;
    return Container(
      key: const Key('data-governance-restore-preview'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.preview_outlined),
              const SizedBox(width: 8),
              Text(
                l10n.dataGovernanceRestorePreview,
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (empty)
            Text(l10n.dataGovernanceRestorePreviewEmpty)
          else
            Text(
              l10n.dataGovernanceRestorePreviewSummary(
                summary.books,
                summary.accounts,
                summary.transactions,
                summary.transactionEntries,
                summary.recurringRules,
                summary.budgets,
                summary.attachments,
                summary.merchantRules,
              ),
              key: const Key('data-governance-restore-summary'),
            ),
          if (isUnencrypted) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dataGovernanceRestoreLegacyUnencrypted,
              key: const Key('data-governance-restore-unencrypted-warning'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
            Text(
              l10n.dataGovernanceRestoreLegacyUnencryptedDetail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (schemaVersion <= 1) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dataGovernanceRestoreNoAttachmentsV1,
              key: const Key('data-governance-restore-v1-warning'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('data-governance-restore-cancel'),
                onPressed: onCancel,
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('data-governance-restore-confirm'),
                onPressed: onConfirm,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(l10n.confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DangerSection extends StatelessWidget {
  const _DangerSection({
    required this.l10n,
    required this.busy,
    required this.onWipe,
  });

  final AppLocalizations l10n;
  final bool busy;
  final VoidCallback? onWipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LedgerlySection(
      title: l10n.dataGovernanceSectionDanger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const Key('data-governance-wipe'),
            leading: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              l10n.dataGovernanceWipe,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: Text(l10n.dataGovernanceWipeSubtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              key: const Key('data-governance-wipe-action'),
              onPressed: onWipe,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.warning_amber_outlined),
              label: Text(
                busy
                    ? l10n.dataGovernanceWipeInProgress
                    : l10n.dataGovernanceWipeAction,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation dialog that requires the user to type the literal word
/// `DELETE` before the destructive button enables.
class _WipeConfirmDialog extends StatefulWidget {
  const _WipeConfirmDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_WipeConfirmDialog> createState() => _WipeConfirmDialogState();
}

class _WipeConfirmDialogState extends State<_WipeConfirmDialog> {
  final _controller = TextEditingController();
  String _typed = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed => _typed.trim() == 'DELETE';

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      key: const Key('data-governance-wipe-dialog'),
      title: Text(l10n.dataGovernanceWipeConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.dataGovernanceWipeConfirmBody),
          const SizedBox(height: 12),
          TextField(
            key: const Key('data-governance-wipe-input'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.dataGovernanceWipeConfirmHint,
              border: const OutlineInputBorder(),
              errorText: _typed.isEmpty || _confirmed
                  ? null
                  : l10n.dataGovernanceWipeConfirmError,
            ),
            onChanged: (value) => setState(() => _typed = value),
            onSubmitted: (_) {
              if (_confirmed) Navigator.pop(context, true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('data-governance-wipe-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(l10n.dataGovernanceWipeAction),
        ),
      ],
    );
  }
}

/// Confirmation dialog that summarises what the restore will overwrite
/// and informs the user that a safety copy was written.
class _RestoreConfirmDialog extends StatelessWidget {
  const _RestoreConfirmDialog({
    required this.summary,
    required this.l10n,
  });

  final BackupSummary summary;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('data-governance-restore-dialog'),
      title: Text(l10n.dataGovernanceRestoreConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.dataGovernanceRestorePreviewSummary(
              summary.books,
              summary.accounts,
              summary.transactions,
              summary.transactionEntries,
              summary.recurringRules,
              summary.budgets,
              summary.attachments,
              summary.merchantRules,
            ),
          ),
          const SizedBox(height: 12),
          // Note: the safety path is known only after the dialog closes
          // and `writeSafetyBackup` runs. We mention the mechanism here
          // and the caller shows the actual path in a follow-up snack.
          Text(l10n.dataGovernanceRestoreConfirmBody('safety-backup')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('data-governance-restore-dialog-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

/// Compact "上次备份: X" card rendered above the backup section.
/// Shows the relative age, or "从未备份" when no record exists.
class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({
    required this.l10n,
    required this.metadata,
    required this.now,
  });

  final AppLocalizations l10n;
  final BackupMetadata metadata;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localAt = metadata.lastBackupAt?.toLocal();
    final ageText = localAt == null
        ? l10n.dataGovernanceStatusNever
        : l10n.dataGovernanceStatusRecent(_formatRelativeAge(now, localAt));
    final detailText = localAt == null
        ? null
        : l10n.dataGovernanceStatusAt(
            _formatLocalDate(localAt),
            _formatLocalTime(localAt),
          );
    final attachmentsText = (metadata.lastAttachmentCount == 0)
        ? null
        : l10n.dataGovernanceStatusAttachments(
            metadata.lastAttachmentCount,
            _formatAttachmentSize(metadata.lastAttachmentSizeBytes),
          );
    return Container(
      key: const Key('data-governance-status-card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            metadata.hasBackup
                ? (metadata.lastBackupEncrypted
                    ? Icons.lock_outlined
                    : Icons.cloud_done_outlined)
                : Icons.cloud_off_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dataGovernanceStatusTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ageText,
                  key: const Key('data-governance-status-age'),
                  style: theme.textTheme.titleMedium,
                ),
                if (detailText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detailText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (attachmentsText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    attachmentsText,
                    key: const Key('data-governance-status-attachments'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (metadata.lastBackupEncrypted) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.dataGovernanceStatusEncrypted,
                    key: const Key('data-governance-status-encrypted'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatRelativeAge(DateTime now, DateTime localAt) {
    final age = now.difference(localAt);
    if (age.isNegative) return '刚刚';
    if (age.inMinutes < 1) return '刚刚';
    if (age.inHours < 1) {
      final m = age.inMinutes;
      return '$m 分钟';
    }
    if (age.inDays < 1) {
      final h = age.inHours;
      return '$h 小时';
    }
    if (age.inDays < 30) {
      final d = age.inDays;
      return '$d 天';
    }
    if (age.inDays < 365) {
      final months = (age.inDays / 30).floor();
      return '$months 个月';
    }
    final years = (age.inDays / 365).floor();
    return '$years 年';
  }

  static String _formatLocalDate(DateTime localAt) {
    final y = localAt.year.toString().padLeft(4, '0');
    final m = localAt.month.toString().padLeft(2, '0');
    final d = localAt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatLocalTime(DateTime localAt) {
    final h = localAt.hour.toString().padLeft(2, '0');
    final mi = localAt.minute.toString().padLeft(2, '0');
    return '$h:$mi';
  }

  /// Render attachment sizes in MB with one decimal place. We surface
  /// a `0.0 MB` placeholder when the backup metadata recorded zero
  /// bytes so the UI never shows an empty gap.
  static String _formatAttachmentSize(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    final formatted = megabytes.toStringAsFixed(1);
    return '$formatted MB';
  }
}

/// Soft reminder shown when the last backup is older than the
/// staleness threshold. Non-blocking — the user can still browse,
/// restore, or wipe while the banner is visible.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    required this.l10n,
    required this.days,
    required this.onAction,
  });

  final AppLocalizations l10n;
  final int days;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: const Key('data-governance-stale-banner'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.dataGovernanceStaleBannerTitle(days),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            key: const Key('data-governance-stale-banner-action'),
            onPressed: onAction,
            icon: const Icon(Icons.save_alt_outlined, size: 18),
            label: Text(l10n.dataGovernanceStaleBannerAction),
            style: FilledButton.styleFrom(
              backgroundColor: colors.onTertiaryContainer,
              foregroundColor: colors.tertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-select chip row that lets the user scope the next backup to a
/// subset of books. Rendered above the export button when more than one
/// book exists. An empty selection means "every book" — the default
/// Phase 6 behaviour — which the helper text under the chips makes
/// explicit so the user never wonders whether a deselected chip is
/// still being exported.
class _BookSelector extends StatelessWidget {
  const _BookSelector({
    required this.l10n,
    required this.availableBooks,
    required this.selectedBookIds,
    required this.onToggle,
  });

  final AppLocalizations l10n;
  final List<Book> availableBooks;
  final Set<String> selectedBookIds;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onToggle == null;
    return Padding(
      key: const Key('data-governance-book-selector'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dataGovernanceSelectBooks,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dataGovernanceSelectBooksHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final book in availableBooks)
                FilterChip(
                  key: Key('data-governance-book-chip-${book.id}'),
                  label: Text(book.name),
                  selected: selectedBookIds.contains(book.id),
                  onSelected:
                      disabled ? null : (selected) => onToggle!(book.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Password prompt used when restoring a v3 encrypted backup. Lockout
/// lives entirely in this dialog so [BackupService] stays pure.
class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({
    required this.l10n,
    required this.onUnlock,
  });

  final AppLocalizations l10n;
  final Future<BackupDocument> Function(String password) onUnlock;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _controller = TextEditingController();
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  Timer? _ticker;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _isLocked {
    final until = _lockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get _lockSecondsRemaining {
    final until = _lockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  void _ensureTicker() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isLocked) {
        _ticker?.cancel();
        _ticker = null;
      }
      setState(() {});
    });
  }

  Future<void> _submit() async {
    if (_busy || _isLocked) return;
    final password = _controller.text;
    if (password.length < 8) {
      setState(() => _error = widget.l10n.dataGovernancePasswordTooShort);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final document = await widget.onUnlock(password);
      if (!mounted) return;
      Navigator.pop(context, document);
    } on BackupPasswordException {
      if (!mounted) return;
      final nextFailed = _failedAttempts + 1;
      DateTime? lockedUntil;
      if (nextFailed >= kBackupUnlockMaxAttempts) {
        lockedUntil = DateTime.now().add(kBackupUnlockLockDuration);
        _ensureTicker();
      }
      setState(() {
        _busy = false;
        _failedAttempts =
            nextFailed >= kBackupUnlockMaxAttempts ? 0 : nextFailed;
        _lockedUntil = lockedUntil ?? _lockedUntil;
        _error = widget.l10n.dataGovernanceUnlockWrongPassword;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final locked = _isLocked;
    final remaining = _lockSecondsRemaining;
    return AlertDialog(
      key: const Key('data-governance-unlock-dialog'),
      title: Text(l10n.dataGovernanceUnlockPrompt),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('data-governance-unlock-password'),
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !locked && !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.dataGovernanceUnlockPrompt,
              border: const OutlineInputBorder(),
              errorText: locked
                  ? l10n.dataGovernanceUnlockLockedFor(remaining)
                  : _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('data-governance-unlock-submit'),
          onPressed: locked || _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.confirm),
        ),
      ],
    );
  }
}

// Tiny helpers to keep call sites readable without fighting analyzer
// preferences around `showDialog`.
Future<T?> showDialogDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(context: context, builder: builder);
}
