import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../providers.dart';

class ExportPage extends ConsumerWidget {
  const ExportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final csv = ref.watch(exportCsvProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.exportCsv)),
      body: csv.when(
        data: (text) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(text),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.copiedToClipboard)),
                    );
                  }
                },
                child: Text(l10n.copyCsv),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('export-save'),
                onPressed: () async {
                  final stamp = DateTime.now().toIso8601String().split('T').first;
                  await ref.read(userFilePortProvider).saveTextFile(
                        fileName: 'ledgerly-$stamp.csv',
                        contents: text,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.csvSaved)),
                    );
                  }
                },
                child: Text(l10n.saveCsvFile),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
