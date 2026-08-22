import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_endpoint_editor.dart';
import '../providers.dart';
import '../widgets/settings_content.dart';
import '../../l10n/l10n.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _loggingOut = false;
  bool _changingEndpoint = false;

  Future<void> _changeEndpoint() async {
    final activeEndpoint = ref.read(apiEndpointProvider);
    final current = activeEndpoint?.baseUrl ?? '';
    final endpointController = ref.read(apiEndpointControllerProvider);
    final selected = await showApiEndpointEditorDialog(
      context: context,
      controller: endpointController,
      currentValue: current,
    );
    if (selected == null || selected == current || !mounted) return;

    final switchesToLocal = selected.isEmpty;
    final switchesFromLocal = activeEndpoint == null;

    final l10n = l10nOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          switchesToLocal
              ? l10n.switchToLocalTitle
              : switchesFromLocal
                  ? l10n.connectApiTitle
                  : l10n.switchApiTitle,
        ),
        content: Text(
          switchesToLocal ? l10n.switchToLocalBody : l10n.connectApiBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            key: const Key('settings-api-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(
              switchesToLocal ? Icons.cloud_off_outlined : Icons.swap_horiz,
            ),
            label: Text(
              switchesToLocal ? l10n.localOnlyStorage : l10n.confirmConnect,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _changingEndpoint = true);
    if (!switchesFromLocal) {
      await ref.read(authControllerProvider).logout();
    }
    try {
      await endpointController.save(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
            SnackBar(content: Text(l10nOf(context).apiSettingsSaveFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _changingEndpoint = false);
      }
    }
  }

  Future<void> _confirmLogout() async {
    final l10n = l10nOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmLogoutTitle),
        content: Text(l10n.confirmLogoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.logout),
            label: Text(l10n.logOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    await ref.read(authControllerProvider).logout();
    if (mounted) {
      setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final endpoint = ref.watch(apiEndpointProvider);
    final isLocal = endpoint == null;
    return Scaffold(
      body: SafeArea(
        child: SettingsContent(
          isLocal: isLocal,
          endpointLabel:
              endpoint?.baseUrl ?? l10nOf(context).endpointUnsetLocal,
          loggingOut: _loggingOut,
          changingEndpoint: _changingEndpoint,
          onChangeEndpoint: _changingEndpoint ? null : _changeEndpoint,
          onSync: isLocal ? null : () => context.go('/settings/sync'),
          onConflicts: isLocal ? null : () => context.go('/settings/conflicts'),
          onExport: () => context.go('/settings/export'),
          onImport: () => context.go('/settings/import'),
          onCategories: () => context.go('/settings/categories'),
          onBudgets: () => context.go('/settings/budgets'),
          onRecurring: () => context.go('/settings/recurring'),
          onAttachments: () => context.go('/settings/attachments'),
          onLock: () => context.go('/settings/lock'),
          onAi: () => context.go('/settings/ai'),
          onLogout: _loggingOut || _changingEndpoint ? null : _confirmLogout,
        ),
      ),
    );
  }
}
