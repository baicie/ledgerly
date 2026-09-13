import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup_encryption.dart';
import '../../application/backup_catalog_store.dart';
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
  bool _incrementalBackup = false;
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  /// True when [_pendingDocument] came from a plaintext v1/v2 file so
  /// the restore preview can nudge the user toward encrypted backups.
  bool _pendingIsUnencrypted = false;

  /// Replace remains the default to preserve Phase 6-12 behaviour.
  /// Merge is opt-in from the restore preview.
  BackupRestoreMode _restoreMode = BackupRestoreMode.replace;

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
      if (result.ran) ref.invalidate(backupCatalogProvider);
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
        incremental: _incrementalBackup && password == null,
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
      ref.invalidate(backupCatalogProvider);
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

  Future<void> _confirmCleanupBackups() async {
    final l10n = l10nOf(context);
    final confirmed = await showDialogDialog<bool>(
      context: context,
      builder: (dialogContext) => _CleanupConfirmDialog(l10n: l10n),
    );
    if (confirmed != true || !mounted) return;

    _setBusy(true);
    try {
      final result = await _service.cleanupBackups();
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(backupCatalogProvider);
      final size = _formatMegabytes(result.freedBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failedCount == 0
                ? result.deletedCount == 0
                    ? l10n.dataGovernanceCleanupNoChanges
                    : l10n.dataGovernanceCleanupSuccess(
                        result.deletedCount,
                        size,
                      )
                : l10n.dataGovernanceCleanupPartial(
                    result.deletedCount,
                    size,
                    result.failedCount,
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceCleanupFailed('$error')),
        ),
      );
    }
  }

  Future<void> _consolidateLatestBackup() async {
    final l10n = l10nOf(context);
    final password = await showDialogDialog<String>(
      context: context,
      builder: (dialogContext) => _PortableBackupPasswordDialog(l10n: l10n),
    );
    if (!mounted || password == null) return;

    _setBusy(true);
    try {
      final result = await _service.consolidateLatest(
        password: password.isEmpty ? null : password,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dataGovernanceConsolidateNoChanges)),
        );
        return;
      }
      setState(() {
        _lastBackupPath = result.path;
        _busy = false;
      });
      ref.invalidate(backupMetadataProvider);
      ref.invalidate(backupCatalogProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.dataGovernanceConsolidateSuccess(
              result.path,
              _formatMegabytes(result.sizeBytes),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceConsolidateFailed('$error')),
        ),
      );
    }
  }

  Future<void> _verifyBackups() async {
    final l10n = l10nOf(context);
    _setBusy(true);
    try {
      final report = await _service.verifyBackups();
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(backupCatalogProvider);
      if (report.entries.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dataGovernanceVerifyNoBackups)),
        );
        return;
      }
      if (report.missingCount == 0 && report.corruptedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.dataGovernanceVerifyAllHealthy(report.healthyCount),
            ),
          ),
        );
        return;
      }
      await showDialogDialog<void>(
        context: context,
        builder: (dialogContext) => _IntegrityReportDialog(
          l10n: l10n,
          report: report,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceVerifyFailed('$error')),
        ),
      );
    }
  }

  Future<void> _drillLatestBackup() async {
    final result = await _runRecoveryDrill(
      (password) => _service.runRecoveryDrill(password: password),
    );
    if (!mounted || result == null) return;
    await _showRecoveryDrillResult(result);
  }

  Future<BackupRecoveryDrillResult?> _runRecoveryDrill(
    Future<BackupRecoveryDrillResult> Function(String? password) run,
  ) async {
    final l10n = l10nOf(context);
    _setBusy(true);
    try {
      final result = await run(null);
      if (!mounted) return null;
      setState(() => _busy = false);
      return result;
    } on BackupPasswordException {
      if (!mounted) return null;
      setState(() => _busy = false);
      return showDialogDialog<BackupRecoveryDrillResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            _PasswordSubmitDialog<BackupRecoveryDrillResult>(
          l10n: l10n,
          title: l10n.dataGovernanceRecoveryDrillPasswordTitle,
          dialogKey: const Key('data-governance-drill-password-dialog'),
          passwordKey: const Key('data-governance-drill-password'),
          submitKey: const Key('data-governance-drill-submit'),
          onPassword: (password) => run(password),
        ),
      );
    } catch (error) {
      if (!mounted) return null;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceRecoveryDrillFailed('$error')),
        ),
      );
      return null;
    }
  }

  Future<void> _showRecoveryDrillResult(
    BackupRecoveryDrillResult result,
  ) {
    final l10n = l10nOf(context);
    return showDialogDialog<void>(
      context: context,
      builder: (dialogContext) => _RecoveryDrillResultDialog(
        l10n: l10n,
        result: result,
      ),
    );
  }

  Future<void> _shareCatalogArtifact(BackupArtifact artifact) async {
    final l10n = l10nOf(context);
    try {
      await _service.shareFile(artifact.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceBackupFailed('$error')),
        ),
      );
    }
  }

  Future<void> _drillCatalogArtifact(BackupArtifact artifact) async {
    final result = await _runRecoveryDrill(
      (password) => _service.runCatalogRecoveryDrill(
        artifact,
        password: password,
      ),
    );
    if (!mounted || result == null) return;
    await _showRecoveryDrillResult(result);
  }

  Future<void> _loadCatalogArtifactForRestore(
    BackupArtifact artifact,
  ) async {
    final l10n = l10nOf(context);
    _setBusy(true);
    try {
      var document = await _service.readCatalogBackup(artifact);
      if (!mounted) return;
      final wasEncrypted = document.isEncrypted;
      if (wasEncrypted) {
        setState(() => _busy = false);
        final unlocked = await showDialogDialog<BackupDocument>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => _PasswordSubmitDialog<BackupDocument>(
            l10n: l10n,
            title: l10n.dataGovernanceArtifactUnlockPrompt,
            dialogKey: const Key('data-governance-artifact-password-dialog'),
            passwordKey: const Key('data-governance-artifact-password'),
            submitKey: const Key('data-governance-artifact-password-submit'),
            onPassword: (password) => _service.unlockCatalogBackup(
              artifact,
              password: password,
            ),
          ),
        );
        if (!mounted || unlocked == null) return;
        document = unlocked;
      }
      setState(() {
        _pendingDocument = document;
        _pendingIsUnencrypted = !wasEncrypted;
        _restoreMode = BackupRestoreMode.replace;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dataGovernanceArtifactRestoreLoaded)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceArtifactLoadFailed('$error')),
        ),
      );
    }
  }

  Future<void> _deleteCatalogArtifact(BackupArtifact artifact) async {
    final l10n = l10nOf(context);
    final confirmed = await showDialogDialog<bool>(
      context: context,
      builder: (dialogContext) => _ArtifactDeleteConfirmDialog(
        l10n: l10n,
        artifact: artifact,
      ),
    );
    if (confirmed != true || !mounted) return;

    _setBusy(true);
    try {
      final freedBytes = await _service.deleteCatalogArtifact(artifact);
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(backupCatalogProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.dataGovernanceArtifactDeleteSuccess(
              _formatMegabytes(freedBytes),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.dataGovernanceArtifactDeleteFailed('$error')),
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
        _restoreMode = BackupRestoreMode.replace;
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
      builder: (dialogContext) => _PasswordSubmitDialog<BackupDocument>(
        l10n: l10n,
        title: l10n.dataGovernanceUnlockPrompt,
        dialogKey: const Key('data-governance-unlock-dialog'),
        passwordKey: const Key('data-governance-unlock-password'),
        submitKey: const Key('data-governance-unlock-submit'),
        onPassword: (password) => _service.unlockEncrypted(
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
      _restoreMode = BackupRestoreMode.replace;
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
        mode: _restoreMode,
      ),
    );
    if (confirmed != true || !mounted) return;

    _setBusy(true);
    String safetyPath;
    BackupMergeResult? mergeResult;
    try {
      safetyPath = await _service.writeSafetyBackup();
      if (_restoreMode == BackupRestoreMode.merge) {
        mergeResult = await _service.merge(document);
      } else {
        await _service.restore(document);
      }
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
      _restoreMode = BackupRestoreMode.replace;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mergeResult == null
              ? l10n.dataGovernanceRestoreSuccess
              : mergeResult.changed
                  ? l10n.dataGovernanceRestoreMergeSuccess(
                      mergeResult.addedBooks,
                      mergeResult.replacedBooks,
                      mergeResult.skippedBooks,
                    )
                  : l10n.dataGovernanceRestoreMergeNoChanges,
        ),
      ),
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
    ref.invalidate(backupCatalogProvider);
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
    final catalog =
        ref.watch(backupCatalogProvider).maybeWhen<List<BackupArtifact>>(
              data: (value) => value,
              orElse: () => const <BackupArtifact>[],
            );
    final localBackupBytes = catalog.fold<int>(
      0,
      (sum, artifact) => sum + artifact.sizeBytes,
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
                  lastBackupIncremental: metadata.lastBackupIncremental,
                  localBackupCount: catalog.length,
                  localBackupSizeBytes: localBackupBytes,
                  artifacts: catalog,
                  currentBaseId: metadata.baseBackupId,
                  latestBackupId: metadata.lastBackupId,
                  pendingSummary: _pendingDocument?.summary,
                  pendingIsUnencrypted: _pendingIsUnencrypted,
                  pendingSchemaVersion: _pendingDocument?.schemaVersion,
                  restoreMode: _restoreMode,
                  encryptBackup: _encryptBackup,
                  incrementalBackup: _incrementalBackup,
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
                          setState(() {
                            _encryptBackup = value;
                            if (value) _incrementalBackup = false;
                          });
                          _syncExportPasswordProvider();
                        },
                  onIncrementalChanged: _busy || _encryptBackup
                      ? null
                      : (value) => setState(() => _incrementalBackup = value),
                  onPasswordChanged: (_) {
                    setState(() {});
                    _syncExportPasswordProvider();
                  },
                  onExport: _busy || !_exportPasswordReady
                      ? null
                      : () => _exportBackup(bookIds: exportSelection),
                  onToggleBook: _busy ? null : _toggleBookSelection,
                  onShare: _busy ||
                          _lastBackupPath == null ||
                          metadata.lastBackupIncremental
                      ? null
                      : () => _shareBackup(_lastBackupPath!),
                  onCleanup:
                      _busy || catalog.isEmpty ? null : _confirmCleanupBackups,
                  onVerify: _busy || catalog.isEmpty ? null : _verifyBackups,
                  onRecoveryDrill: _busy || metadata.lastBackupPath == null
                      ? null
                      : _drillLatestBackup,
                  onArtifactShare: _busy ? null : _shareCatalogArtifact,
                  onArtifactDrill: _busy ? null : _drillCatalogArtifact,
                  onArtifactRestore:
                      _busy ? null : _loadCatalogArtifactForRestore,
                  onArtifactDelete: _busy ? null : _deleteCatalogArtifact,
                  onConsolidate: _busy || !metadata.lastBackupIncremental
                      ? null
                      : _consolidateLatestBackup,
                  onPickRestore: _busy ? null : _pickRestoreFile,
                  onRestoreModeChanged: _busy
                      ? null
                      : (mode) => setState(() => _restoreMode = mode),
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
    required this.lastBackupIncremental,
    required this.localBackupCount,
    required this.localBackupSizeBytes,
    required this.artifacts,
    required this.currentBaseId,
    required this.latestBackupId,
    required this.pendingSummary,
    required this.pendingIsUnencrypted,
    required this.pendingSchemaVersion,
    required this.restoreMode,
    required this.encryptBackup,
    required this.incrementalBackup,
    required this.passwordController,
    required this.passwordConfirmController,
    required this.autoBackupEnabled,
    required this.autoBackupIntervalDays,
    required this.onAutoBackupChanged,
    required this.onAutoBackupIntervalChanged,
    required this.onEncryptChanged,
    required this.onIncrementalChanged,
    required this.onPasswordChanged,
    required this.onExport,
    required this.onToggleBook,
    required this.onShare,
    required this.onCleanup,
    required this.onVerify,
    required this.onRecoveryDrill,
    required this.onArtifactShare,
    required this.onArtifactDrill,
    required this.onArtifactRestore,
    required this.onArtifactDelete,
    required this.onConsolidate,
    required this.onPickRestore,
    required this.onRestoreModeChanged,
    required this.onCancelRestore,
    required this.onConfirmRestore,
  });

  final AppLocalizations l10n;
  final bool busy;
  final List<Book> availableBooks;
  final Set<String> selectedBookIds;
  final String? lastBackupPath;
  final bool lastBackupIncremental;
  final int localBackupCount;
  final int localBackupSizeBytes;
  final List<BackupArtifact> artifacts;
  final String? currentBaseId;
  final String? latestBackupId;
  final BackupSummary? pendingSummary;
  final bool pendingIsUnencrypted;
  final int? pendingSchemaVersion;
  final BackupRestoreMode restoreMode;
  final bool encryptBackup;
  final bool incrementalBackup;
  final TextEditingController passwordController;
  final TextEditingController passwordConfirmController;
  final bool autoBackupEnabled;
  final int autoBackupIntervalDays;
  final ValueChanged<bool>? onAutoBackupChanged;
  final ValueChanged<int>? onAutoBackupIntervalChanged;
  final ValueChanged<bool>? onEncryptChanged;
  final ValueChanged<bool>? onIncrementalChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback? onExport;
  final ValueChanged<String>? onToggleBook;
  final VoidCallback? onShare;
  final VoidCallback? onCleanup;
  final VoidCallback? onVerify;
  final VoidCallback? onRecoveryDrill;
  final ValueChanged<BackupArtifact>? onArtifactShare;
  final ValueChanged<BackupArtifact>? onArtifactDrill;
  final ValueChanged<BackupArtifact>? onArtifactRestore;
  final ValueChanged<BackupArtifact>? onArtifactDelete;
  final VoidCallback? onConsolidate;
  final VoidCallback? onPickRestore;
  final ValueChanged<BackupRestoreMode>? onRestoreModeChanged;
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
          CheckboxListTile(
            key: const Key('data-governance-incremental-checkbox'),
            value: incrementalBackup,
            onChanged: onIncrementalChanged == null
                ? null
                : (value) => onIncrementalChanged!(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.dataGovernanceIncrementalBackup),
            subtitle: Text(
              encryptBackup
                  ? l10n.dataGovernanceIncrementalEncryptedDisabled
                  : l10n.dataGovernanceIncrementalBackupHint,
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
                if (lastBackupIncremental)
                  OutlinedButton.icon(
                    key: const Key('data-governance-consolidate-action'),
                    onPressed: onConsolidate,
                    icon: const Icon(Icons.archive_outlined),
                    label: Text(l10n.dataGovernanceConsolidateBackup),
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
          if (localBackupCount > 0) ...[
            ListTile(
              key: const Key('data-governance-backup-catalog'),
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(
                l10n.dataGovernanceLocalBackups(
                  localBackupCount,
                  _formatMegabytes(localBackupSizeBytes),
                ),
              ),
              subtitle: Text(l10n.dataGovernanceCleanupSubtitle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('data-governance-verify-action'),
                    onPressed: onVerify,
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(l10n.dataGovernanceVerifyBackups),
                  ),
                  OutlinedButton.icon(
                    key: const Key('data-governance-drill-action'),
                    onPressed: onRecoveryDrill,
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: Text(l10n.dataGovernanceRecoveryDrill),
                  ),
                  OutlinedButton.icon(
                    key: const Key('data-governance-cleanup-action'),
                    onPressed: onCleanup,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(l10n.dataGovernanceCleanupBackups),
                  ),
                ],
              ),
            ),
            _BackupArtifactList(
              l10n: l10n,
              artifacts: artifacts,
              currentBaseId: currentBaseId,
              latestBackupId: latestBackupId,
              busy: busy,
              onShare: onArtifactShare,
              onDrill: onArtifactDrill,
              onRestore: onArtifactRestore,
              onDelete: onArtifactDelete,
            ),
          ],
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
              restoreMode: restoreMode,
              onRestoreModeChanged: onRestoreModeChanged,
              onCancel: onCancelRestore,
              onConfirm: onConfirmRestore,
              busy: busy,
            ),
        ],
      ),
    );
  }
}

enum _BackupArtifactAction { share, drill, restore, delete }

class _BackupArtifactList extends StatelessWidget {
  const _BackupArtifactList({
    required this.l10n,
    required this.artifacts,
    required this.currentBaseId,
    required this.latestBackupId,
    required this.busy,
    required this.onShare,
    required this.onDrill,
    required this.onRestore,
    required this.onDelete,
  });

  final AppLocalizations l10n;
  final List<BackupArtifact> artifacts;
  final String? currentBaseId;
  final String? latestBackupId;
  final bool busy;
  final ValueChanged<BackupArtifact>? onShare;
  final ValueChanged<BackupArtifact>? onDrill;
  final ValueChanged<BackupArtifact>? onRestore;
  final ValueChanged<BackupArtifact>? onDelete;

  @override
  Widget build(BuildContext context) {
    final dependentBaseIds = <String>{
      for (final artifact in artifacts)
        if (artifact.baseBackupId != null) artifact.baseBackupId!,
    };
    return ExpansionTile(
      key: const Key('data-governance-artifact-list'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(l10n.dataGovernanceArtifactListTitle),
      children: [
        for (final artifact in artifacts)
          _BackupArtifactTile(
            l10n: l10n,
            artifact: artifact,
            isCurrentBase: artifact.backupId == currentBaseId,
            isLatest: artifact.backupId == latestBackupId,
            isProtected: artifact.backupId == currentBaseId ||
                artifact.backupId == latestBackupId ||
                dependentBaseIds.contains(artifact.backupId),
            busy: busy,
            onShare: onShare,
            onDrill: onDrill,
            onRestore: onRestore,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

class _BackupArtifactTile extends StatelessWidget {
  const _BackupArtifactTile({
    required this.l10n,
    required this.artifact,
    required this.isCurrentBase,
    required this.isLatest,
    required this.isProtected,
    required this.busy,
    required this.onShare,
    required this.onDrill,
    required this.onRestore,
    required this.onDelete,
  });

  final AppLocalizations l10n;
  final BackupArtifact artifact;
  final bool isCurrentBase;
  final bool isLatest;
  final bool isProtected;
  final bool busy;
  final ValueChanged<BackupArtifact>? onShare;
  final ValueChanged<BackupArtifact>? onDrill;
  final ValueChanged<BackupArtifact>? onRestore;
  final ValueChanged<BackupArtifact>? onDelete;

  String get _kindLabel => switch (artifact.kind) {
        BackupArtifactKind.full => l10n.dataGovernanceArtifactKindFull,
        BackupArtifactKind.incremental =>
          l10n.dataGovernanceArtifactKindIncremental,
        BackupArtifactKind.encrypted =>
          l10n.dataGovernanceArtifactKindEncrypted,
      };

  String get _sourceLabel => switch (artifact.source) {
        BackupArtifactSource.manual => l10n.dataGovernanceArtifactSourceManual,
        BackupArtifactSource.automatic =>
          l10n.dataGovernanceArtifactSourceAutomatic,
        BackupArtifactSource.safety => l10n.dataGovernanceArtifactSourceSafety,
      };

  IconData get _kindIcon => switch (artifact.kind) {
        BackupArtifactKind.full => Icons.archive_outlined,
        BackupArtifactKind.incremental => Icons.layers_outlined,
        BackupArtifactKind.encrypted => Icons.lock_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = artifact.createdAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final labels = <String>[
      _kindLabel,
      _sourceLabel,
      if (isCurrentBase) l10n.dataGovernanceArtifactCurrentBase,
      if (isLatest) l10n.dataGovernanceArtifactLatest,
    ];
    return ListTile(
      key: Key('data-governance-artifact-${artifact.backupId}'),
      leading: Icon(_kindIcon),
      title: Text(artifact.backupId),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(labels.join(' · ')),
          Text(
            '${localizations.formatMediumDate(createdAt)} '
            '${localizations.formatTimeOfDay(
              TimeOfDay.fromDateTime(createdAt),
              alwaysUse24HourFormat: true,
            )}'
            ' · ${_formatMegabytes(artifact.sizeBytes)}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            artifact.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      trailing: PopupMenuButton<_BackupArtifactAction>(
        key: Key('data-governance-artifact-${artifact.backupId}-actions'),
        enabled: !busy,
        tooltip: l10n.dataGovernanceArtifactActions,
        onSelected: (action) {
          switch (action) {
            case _BackupArtifactAction.share:
              onShare?.call(artifact);
              break;
            case _BackupArtifactAction.drill:
              onDrill?.call(artifact);
              break;
            case _BackupArtifactAction.restore:
              onRestore?.call(artifact);
              break;
            case _BackupArtifactAction.delete:
              onDelete?.call(artifact);
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            key: Key('data-governance-artifact-${artifact.backupId}-share'),
            value: _BackupArtifactAction.share,
            enabled: onShare != null,
            child: Text(l10n.dataGovernanceArtifactShare),
          ),
          PopupMenuItem(
            key: Key('data-governance-artifact-${artifact.backupId}-drill'),
            value: _BackupArtifactAction.drill,
            enabled: onDrill != null,
            child: Text(l10n.dataGovernanceArtifactDrill),
          ),
          PopupMenuItem(
            key: Key('data-governance-artifact-${artifact.backupId}-restore'),
            value: _BackupArtifactAction.restore,
            enabled: onRestore != null,
            child: Text(l10n.dataGovernanceArtifactRestore),
          ),
          PopupMenuItem(
            key: Key('data-governance-artifact-${artifact.backupId}-delete'),
            value: _BackupArtifactAction.delete,
            enabled: onDelete != null && !isProtected,
            child: Text(l10n.dataGovernanceArtifactDelete),
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
    required this.restoreMode,
    required this.onRestoreModeChanged,
    required this.onCancel,
    required this.onConfirm,
    required this.busy,
  });

  final AppLocalizations l10n;
  final BackupSummary summary;
  final bool isUnencrypted;
  final int schemaVersion;
  final BackupRestoreMode restoreMode;
  final ValueChanged<BackupRestoreMode>? onRestoreModeChanged;
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
          const SizedBox(height: 12),
          SegmentedButton<BackupRestoreMode>(
            key: const Key('data-governance-restore-mode'),
            segments: [
              ButtonSegment(
                value: BackupRestoreMode.replace,
                icon: const Icon(Icons.swap_horiz),
                label: Text(l10n.dataGovernanceRestoreModeReplace),
              ),
              ButtonSegment(
                value: BackupRestoreMode.merge,
                icon: const Icon(Icons.merge_type),
                label: Text(l10n.dataGovernanceRestoreModeMerge),
              ),
            ],
            selected: {restoreMode},
            onSelectionChanged: onRestoreModeChanged == null
                ? null
                : (selection) => onRestoreModeChanged!(selection.first),
          ),
          if (restoreMode == BackupRestoreMode.merge) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dataGovernanceRestoreMergeHint,
              key: const Key('data-governance-restore-merge-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
                    : Icon(
                        restoreMode == BackupRestoreMode.merge
                            ? Icons.merge_type
                            : Icons.swap_horiz,
                      ),
                label: Text(
                  restoreMode == BackupRestoreMode.merge
                      ? l10n.dataGovernanceRestoreMergeAction
                      : l10n.dataGovernanceRestoreReplaceAction,
                ),
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
    required this.mode,
  });

  final BackupSummary summary;
  final AppLocalizations l10n;
  final BackupRestoreMode mode;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('data-governance-restore-dialog'),
      title: Text(
        mode == BackupRestoreMode.merge
            ? l10n.dataGovernanceRestoreConfirmMergeTitle
            : l10n.dataGovernanceRestoreConfirmTitle,
      ),
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
          Text(
            mode == BackupRestoreMode.merge
                ? l10n.dataGovernanceRestoreConfirmMergeBody('safety-backup')
                : l10n.dataGovernanceRestoreConfirmBody('safety-backup'),
          ),
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

class _CleanupConfirmDialog extends StatelessWidget {
  const _CleanupConfirmDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('data-governance-cleanup-dialog'),
      title: Text(l10n.dataGovernanceCleanupConfirmTitle),
      content: Text(l10n.dataGovernanceCleanupConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('data-governance-cleanup-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.dataGovernanceCleanupBackups),
        ),
      ],
    );
  }
}

class _ArtifactDeleteConfirmDialog extends StatelessWidget {
  const _ArtifactDeleteConfirmDialog({
    required this.l10n,
    required this.artifact,
  });

  final AppLocalizations l10n;
  final BackupArtifact artifact;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('data-governance-artifact-delete-dialog'),
      title: Text(l10n.dataGovernanceArtifactDeleteConfirmTitle),
      content: Text(
        l10n.dataGovernanceArtifactDeleteConfirmBody(artifact.path),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('data-governance-artifact-delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.dataGovernanceArtifactDelete),
        ),
      ],
    );
  }
}

class _PortableBackupPasswordDialog extends StatefulWidget {
  const _PortableBackupPasswordDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_PortableBackupPasswordDialog> createState() =>
      _PortableBackupPasswordDialogState();
}

class _PortableBackupPasswordDialogState
    extends State<_PortableBackupPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _passwordTooShort {
    final password = _passwordController.text;
    return password.isNotEmpty && password.length < 8;
  }

  bool get _passwordMismatch {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    return password.isNotEmpty && confirm.isNotEmpty && password != confirm;
  }

  bool get _canSubmit {
    final password = _passwordController.text;
    if (password.isEmpty) return true;
    return !_passwordTooShort && password == _confirmController.text;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(context, _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      key: const Key('data-governance-portable-password-dialog'),
      title: Text(l10n.dataGovernanceConsolidatePasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.dataGovernanceConsolidatePasswordBody),
          const SizedBox(height: 16),
          TextField(
            key: const Key('data-governance-portable-password'),
            controller: _passwordController,
            autofocus: true,
            obscureText: true,
            onChanged: (value) {
              if (value.isEmpty) _confirmController.clear();
              setState(() {});
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.dataGovernanceConsolidatePasswordLabel,
              border: const OutlineInputBorder(),
              errorText: _passwordTooShort
                  ? l10n.dataGovernancePasswordTooShort
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('data-governance-portable-password-confirm'),
            controller: _confirmController,
            enabled: _passwordController.text.isNotEmpty,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.dataGovernanceConsolidatePasswordConfirm,
              border: const OutlineInputBorder(),
              errorText: _passwordMismatch
                  ? l10n.dataGovernancePasswordMismatch
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('data-governance-portable-password-submit'),
          onPressed: _canSubmit ? _submit : null,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

class _IntegrityReportDialog extends StatelessWidget {
  const _IntegrityReportDialog({
    required this.l10n,
    required this.report,
  });

  final AppLocalizations l10n;
  final BackupVerificationReport report;

  @override
  Widget build(BuildContext context) {
    final issues = [
      for (final entry in report.entries)
        if (entry.status != BackupVerificationStatus.healthy) entry,
    ];
    return AlertDialog(
      key: const Key('data-governance-integrity-dialog'),
      title: Text(l10n.dataGovernanceVerifyIssuesTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.dataGovernanceVerifyIssueSummary(
                report.healthyCount,
                report.missingCount,
                report.corruptedCount,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: issues.length,
                itemBuilder: (context, index) {
                  final entry = issues[index];
                  final missing =
                      entry.status == BackupVerificationStatus.missing;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      missing ? Icons.folder_off_outlined : Icons.error_outline,
                    ),
                    title: Text(entry.artifact.path),
                    subtitle: Text(
                      missing
                          ? l10n.dataGovernanceVerifyMissing
                          : entry.error ?? l10n.dataGovernanceVerifyCorrupted,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

class _RecoveryDrillResultDialog extends StatelessWidget {
  const _RecoveryDrillResultDialog({
    required this.l10n,
    required this.result,
  });

  final AppLocalizations l10n;
  final BackupRecoveryDrillResult result;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('data-governance-drill-result-dialog'),
      title: Text(l10n.dataGovernanceRecoveryDrillSuccessTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.dataGovernanceRecoveryDrillSuccess(
                result.summary.books,
                result.summary.transactions,
                result.summary.attachments,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.dataGovernanceRecoveryDrillSuccessBody),
            const SizedBox(height: 12),
            Text(
              l10n.dataGovernanceRecoveryDrillPath(result.path),
              key: const Key('data-governance-drill-result-path'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
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
                if (metadata.lastBackupIncremental) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.dataGovernanceStatusIncremental,
                    key: const Key('data-governance-status-incremental'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
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

/// Shared password prompt for encrypted restore and recovery drill.
/// Lockout lives in the dialog so [BackupService] stays pure.
class _PasswordSubmitDialog<T> extends StatefulWidget {
  const _PasswordSubmitDialog({
    required this.l10n,
    required this.title,
    required this.dialogKey,
    required this.passwordKey,
    required this.submitKey,
    required this.onPassword,
  });

  final AppLocalizations l10n;
  final String title;
  final Key dialogKey;
  final Key passwordKey;
  final Key submitKey;
  final Future<T> Function(String password) onPassword;

  @override
  State<_PasswordSubmitDialog<T>> createState() =>
      _PasswordSubmitDialogState<T>();
}

class _PasswordSubmitDialogState<T> extends State<_PasswordSubmitDialog<T>> {
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
      final result = await widget.onPassword(password);
      if (!mounted) return;
      Navigator.pop(context, result);
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
      key: widget.dialogKey,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: widget.passwordKey,
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !locked && !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.title,
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
          key: widget.submitKey,
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

String _formatMegabytes(int bytes) {
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// Tiny helpers to keep call sites readable without fighting analyzer
// preferences around `showDialog`.
Future<T?> showDialogDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
}
