import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
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
      final plan = ref.read(authRepositoryProvider).currentSession?.plan;
      setState(() {
        _plan = plan ?? 'unknown';
        _message = null;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    }
  }

  Future<void> _upgrade(String plan) async {
    try {
      final res = await ref.read(syncApiProvider).devUpgrade(plan: plan);
      setState(() {
        _plan = '${res['plan']}';
        _message = L10n.current.upgraded;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.subscription)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(title: Text(l10n.currentPlan), subtitle: Text(_plan)),
          if (_message != null) Text(_message!),
          const Divider(),
          FilledButton(
            onPressed: () => _upgrade('plus'),
            child: Text(l10n.devUpgradePlus),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _upgrade('family'),
            child: Text(l10n.devUpgradeFamily),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _upgrade('free'),
            child: Text(l10n.downgradeFree),
          ),
        ],
      ),
    );
  }
}
