import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_endpoint_editor.dart';
import '../providers.dart';
import '../widgets/settings_content.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool appLock = false;
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          switchesToLocal
              ? '改为仅本地存储？'
              : switchesFromLocal
                  ? '连接 API 服务？'
                  : '切换 API 服务？',
        ),
        content: Text(
          switchesToLocal ? '远端登录会退出，本机账本数据会保留。' : '连接后需要登录服务，本机账本数据会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const Key('settings-api-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(
              switchesToLocal ? Icons.cloud_off_outlined : Icons.swap_horiz,
            ),
            label: Text(switchesToLocal ? '仅本地存储' : '确认连接'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 设置保存失败，仍保持原存储模式。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _changingEndpoint = false);
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('本机账本数据会保留，下次登录后可继续使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
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
    final session = ref.watch(authControllerProvider).state.session;
    final endpoint = ref.watch(apiEndpointProvider);
    final isLocal = endpoint == null;
    return Scaffold(
      body: SafeArea(
        child: SettingsContent(
          isLocal: isLocal,
          planLabel: _planLabel(session?.plan),
          endpointLabel: endpoint?.baseUrl ?? '未设置（仅本地存储）',
          appLock: appLock,
          loggingOut: _loggingOut,
          changingEndpoint: _changingEndpoint,
          onChangeEndpoint: _changingEndpoint ? null : _changeEndpoint,
          onAppLockChanged: (value) => setState(() => appLock = value),
          onSync: isLocal ? null : () => context.go('/settings/sync'),
          onConflicts: isLocal ? null : () => context.go('/settings/conflicts'),
          onExport: () => context.go('/settings/export'),
          onSubscription:
              isLocal ? null : () => context.go('/settings/subscription'),
          onFx: isLocal ? null : () => context.go('/settings/fx'),
          onFamily: isLocal ? null : () => context.go('/settings/family'),
          onBudgets: isLocal ? null : () => context.go('/settings/budgets'),
          onRecurring: isLocal ? null : () => context.go('/settings/recurring'),
          onAttachments:
              isLocal ? null : () => context.go('/settings/attachments'),
          onLogout: _loggingOut || _changingEndpoint ? null : _confirmLogout,
        ),
      ),
    );
  }

  String _planLabel(String? plan) {
    return switch (plan) {
      'free' => 'Free',
      'plus' => 'Plus',
      'family' => 'Family',
      final value? when value.isNotEmpty => value,
      _ => '未知',
    };
  }
}
