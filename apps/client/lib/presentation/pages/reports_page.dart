import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  Map<String, dynamic>? _remote;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  Future<void> _loadRemote() async {
    if (ref.read(apiEndpointProvider) == null) return;
    try {
      final api = ref.read(syncApiProvider);
      final bookId = ref.read(authRepositoryProvider).currentSession?.bookId;
      if (bookId == null) return;
      final month = ref.read(selectedMonthProvider);
      final from = DateTime.utc(month.year, month.month).toIso8601String();
      final to = DateTime.utc(month.year, month.month + 1).toIso8601String();
      final summary = await api.reportSummary(
        bookId: bookId,
        from: from,
        to: to,
      );
      if (mounted) {
        setState(() {
          _remote = summary;
          _remoteError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _remoteError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(categoryReportProvider);
    final month = ref.watch(selectedMonthProvider);
    final isLocal = ref.watch(apiEndpointProvider) == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类报表'),
        actions: isLocal
            ? null
            : [
                IconButton(
                  tooltip: '刷新服务端汇总',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadRemote,
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '本地 · ${month.year}-${month.month.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          report.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const ListTile(title: Text('暂无本地支出数据'));
              }
              return Column(
                children: rows
                    .map(
                      (row) => ListTile(
                        title: Text(row.name),
                        trailing: Text(formatMinor(row.amount)),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
          if (!isLocal) ...[
            const Divider(),
            Text(
              '服务端汇总（plus）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_remoteError != null)
              Text(_remoteError!, style: const TextStyle(color: Colors.red)),
            if (_remote != null) ...[
              ListTile(
                title: const Text('收入'),
                trailing: Text(
                  formatMinor(
                    BigInt.tryParse('${_remote!['incomeMinor']}') ??
                        BigInt.zero,
                  ),
                ),
              ),
              ListTile(
                title: const Text('支出'),
                trailing: Text(
                  formatMinor(
                    BigInt.tryParse('${_remote!['expenseMinor']}') ??
                        BigInt.zero,
                  ),
                ),
              ),
              ListTile(
                title: Text('净额（${_remote!['baseCurrency']}）'),
                trailing: Text(
                  formatMinor(
                    BigInt.tryParse('${_remote!['netMinor']}') ?? BigInt.zero,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
