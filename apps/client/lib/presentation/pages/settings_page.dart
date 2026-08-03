import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool appLock = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
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
        ],
      ),
    );
  }
}
