import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ids.dart';
import '../providers.dart';

class FxRatesPage extends ConsumerStatefulWidget {
  const FxRatesPage({super.key});

  @override
  ConsumerState<FxRatesPage> createState() => _FxRatesPageState();
}

class _FxRatesPageState extends ConsumerState<FxRatesPage> {
  final _quote = TextEditingController(text: 'USD');
  final _rate = TextEditingController(text: '0.14');
  var _busy = false;
  String? _message;
  List<Map<String, dynamic>> _rates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quote.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<String?> _bookId() async {
    final sync = ref.read(syncServiceProvider);
    await sync.ensureSession(
      email: 'local@ledgerly.dev',
      password: 'password123',
    );
    final state =
        await ref.read(ledgerRepositoryProvider).syncState(defaultBookId);
    return state?.remoteBookId;
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final bookId = await _bookId();
      if (bookId == null) return;
      final list = await ref.read(syncApiProvider).listFxRates(bookId: bookId);
      setState(() {
        _rates = list;
        _message = null;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bookId = await _bookId();
      if (bookId == null) return;
      await ref.read(syncApiProvider).upsertFxRate(
            bookId: bookId,
            baseCurrency: 'CNY',
            quoteCurrency: _quote.text.trim().toUpperCase(),
            rate: double.tryParse(_rate.text) ?? 1,
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
      appBar: AppBar(title: const Text('汇率')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _quote,
              decoration: const InputDecoration(labelText: '报价币（相对 CNY）'),
            ),
            TextField(
              controller: _rate,
              decoration: const InputDecoration(labelText: '汇率'),
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('保存'),
            ),
            if (_message != null)
              Text(_message!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: ListView.builder(
                itemCount: _rates.length,
                itemBuilder: (context, i) {
                  final r = _rates[i];
                  return ListTile(
                    title: Text('${r['baseCurrency']} / ${r['quoteCurrency']}'),
                    trailing: Text('${r['rate']}'),
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
