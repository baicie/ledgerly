import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ids.dart';
import '../providers.dart';

class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  final _name = TextEditingController(text: '本月餐饮');
  final _amount = TextEditingController(text: '2000.00');
  var _busy = false;
  String? _message;
  List<Map<String, dynamic>> _budgets = const [];

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
        setState(() => _message = '尚未登录同步，无法加载预算');
        return;
      }
      final list = await ref.read(syncApiProvider).listBudgets(bookId: bookId);
      setState(() {
        _budgets = list;
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
      // Bind to local Food category rewritten to remote scope on server accounts.
      final category = accountKeyFood(bookId);
      await ref.read(syncApiProvider).createBudget(
            bookId: bookId,
            name: _name.text.trim(),
            amountMinor: '${yuan * 100 + cents}',
            categoryAccountId: category,
          );
      await _load();
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '金额（元）'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? '处理中…' : '创建预算（绑定餐饮科目）'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _budgets.length,
                itemBuilder: (context, i) {
                  final b = _budgets[i];
                  final limit =
                      BigInt.tryParse('${b['amountMinor']}') ?? BigInt.zero;
                  final spent =
                      BigInt.tryParse('${b['spentMinor'] ?? '0'}') ??
                          BigInt.zero;
                  final remaining =
                      BigInt.tryParse('${b['remainingMinor'] ?? '0'}') ??
                          (limit - spent);
                  final progress = limit == BigInt.zero
                      ? 0.0
                      : (spent.toDouble() / limit.toDouble()).clamp(0.0, 1.5);
                  return ListTile(
                    title: Text('${b['name']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已用 ${formatMinor(spent)} / 预算 ${formatMinor(limit)} · 剩余 ${formatMinor(remaining)}',
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: progress > 1 ? 1 : progress),
                      ],
                    ),
                    isThreeLine: true,
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
