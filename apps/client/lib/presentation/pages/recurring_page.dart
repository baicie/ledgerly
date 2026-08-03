import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ids.dart';
import '../providers.dart';

class RecurringPage extends ConsumerStatefulWidget {
  const RecurringPage({super.key});

  @override
  ConsumerState<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends ConsumerState<RecurringPage> {
  final _name = TextEditingController(text: '每月房租');
  final _amount = TextEditingController(text: '3000.00');
  var _busy = false;
  var _runNow = true;
  String? _message;
  List<Map<String, dynamic>> _rules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<String?> _remoteBookId() async {
    return ref.read(authRepositoryProvider).currentSession?.bookId;
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final bookId = await _remoteBookId();
      if (bookId == null) {
        setState(() => _message = '尚未登录同步');
        return;
      }
      final list =
          await ref.read(syncApiProvider).listRecurring(bookId: bookId);
      setState(() {
        _rules = list;
        _message = null;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final bookId = await _remoteBookId();
      if (bookId == null) return;
      final parts = _amount.text.split('.');
      final yuan = int.tryParse(parts[0]) ?? 0;
      final cents = parts.length > 1
          ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0
          : 0;
      final minor = yuan * 100 + cents;
      await ref.read(syncApiProvider).createRecurring(
            bookId: bookId,
            name: _name.text.trim(),
            runNow: _runNow,
            payload: {
              'description': _name.text.trim(),
              'entries': [
                {
                  'accountId': accountKeyFood(bookId),
                  'amountMinor': '$minor',
                  'currency': 'CNY',
                },
                {
                  'accountId': accountKeyCash(bookId),
                  'amountMinor': '-$minor',
                  'currency': 'CNY',
                },
              ],
            },
          );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _runNow ? '已创建，Worker 约 1 分钟内入账' : '已创建，明日起由 Worker 入账',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('周期记账')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '规则名称'),
            ),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '金额（元）'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('立即调度（runNow）'),
              value: _runNow,
              onChanged: (v) => setState(() => _runNow = v),
            ),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? '处理中…' : '创建规则'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _rules.length,
                itemBuilder: (context, i) {
                  final r = _rules[i];
                  return ListTile(
                    title: Text('${r['name']}'),
                    subtitle: Text('active=${r['active']}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
