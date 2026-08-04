import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_endpoint_editor.dart';
import '../providers.dart';

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
    final current = ref.read(apiEndpointProvider).baseUrl;
    final endpointController = ref.read(apiEndpointControllerProvider);
    final selected = await showApiEndpointEditorDialog(
      context: context,
      controller: endpointController,
      currentValue: current,
    );
    if (selected == null || selected == current || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换 API 服务？'),
        content: const Text('切换后需要在新服务重新登录，本机账本数据会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const Key('settings-api-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('切换并退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _changingEndpoint = true);
    await ref.read(authControllerProvider).logout();
    try {
      await endpointController.save(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 地址保存失败，仍连接原服务。')),
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
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('当前方案'),
            subtitle: Text(_planLabel(session?.plan)),
          ),
          ListTile(
            key: const Key('settings-api-edit'),
            leading: const Icon(Icons.dns_outlined),
            title: const Text('API 服务'),
            subtitle: Text(endpoint.baseUrl),
            trailing: _changingEndpoint
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_outlined),
            enabled: !_changingEndpoint,
            onTap: _changingEndpoint ? null : _changeEndpoint,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('应用锁'),
            subtitle: const Text('基础开关（生物识别后续接入）'),
            value: appLock,
            onChanged: (v) => setState(() => appLock = v),
          ),
          ListTile(
            title: const Text('同步中心'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/sync'),
          ),
          ListTile(
            title: const Text('冲突处理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/conflicts'),
          ),
          ListTile(
            title: const Text('导出 CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/export'),
          ),
          const Divider(),
          ListTile(
            title: const Text('订阅权益'),
            subtitle: const Text('Free / Plus / Family'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/subscription'),
          ),
          ListTile(
            title: const Text('汇率'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/fx'),
          ),
          ListTile(
            title: const Text('家庭共享'),
            subtitle: const Text('需 Family 方案'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/family'),
          ),
          ListTile(
            title: const Text('预算'),
            subtitle: const Text('月度预算与进度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/budgets'),
          ),
          ListTile(
            title: const Text('周期记账'),
            subtitle: const Text('规则由 Job Worker 入账'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/recurring'),
          ),
          ListTile(
            title: const Text('附件'),
            subtitle: const Text('需 Plus · HMAC 直传'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/attachments'),
          ),
          const Divider(),
          ListTile(
            key: const Key('settings-logout'),
            leading: _loggingOut
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
            title: Text(
              '退出登录',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            enabled: !_loggingOut && !_changingEndpoint,
            onTap: _loggingOut || _changingEndpoint ? null : _confirmLogout,
          ),
        ],
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
