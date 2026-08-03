import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  String _plan = 'unknown';
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final sync = ref.read(syncServiceProvider);
      await sync.ensureSession(
        email: 'local@ledgerly.dev',
        password: 'password123',
      );
      // Re-login to read plan from token response stored flow — upgrade returns plan.
      setState(() {
        _plan = 'free（登录后可升级）';
        _message = null;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    }
  }

  Future<void> _upgrade(String plan) async {
    try {
      final sync = ref.read(syncServiceProvider);
      await sync.ensureSession(
        email: 'local@ledgerly.dev',
        password: 'password123',
      );
      final res = await ref.read(syncApiProvider).devUpgrade(plan: plan);
      setState(() {
        _plan = '${res['plan']}';
        _message = '已升级';
      });
    } catch (e) {
      setState(() => _message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('订阅权益')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(title: const Text('当前方案'), subtitle: Text(_plan)),
          if (_message != null) Text(_message!),
          const Divider(),
          FilledButton(
            onPressed: () => _upgrade('plus'),
            child: const Text('开发升级 Plus（附件/高级报表）'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _upgrade('family'),
            child: const Text('开发升级 Family（邀请）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _upgrade('free'),
            child: const Text('降回 Free'),
          ),
        ],
      ),
    );
  }
}
