import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class TransactionRevisionsPage extends ConsumerStatefulWidget {
  const TransactionRevisionsPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionRevisionsPage> createState() =>
      _TransactionRevisionsPageState();
}

class _TransactionRevisionsPageState
    extends ConsumerState<TransactionRevisionsPage> {
  List<Map<String, dynamic>> _rows = const [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sync = ref.read(syncServiceProvider);
      await sync.syncNow();
      final bookId = ref.read(authRepositoryProvider).currentSession?.bookId;
      if (bookId == null) {
        setState(() => _error = '无远端账本');
        return;
      }
      final rows = await ref.read(syncApiProvider).listRevisions(
            bookId: bookId,
            transactionId: widget.transactionId,
          );
      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史版本')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    return ListTile(
                      title: Text('v${r['version']} · ${r['operation']}'),
                      subtitle: Text('${r['createdAt'] ?? r['id']}'),
                    );
                  },
                ),
    );
  }
}
