import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../providers.dart';

class SyncCenterPage extends ConsumerWidget {
  const SyncCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final status = ref.watch(syncStatusProvider);
    final isLocal = ref.watch(apiEndpointProvider) == null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncCenter)),
      body: status.when(
        data: (s) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isLocal) ...[
                Text(
                  l10n.localOnlyStorage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
              ],
              Text(l10n.statusLabel(s.label)),
              Text(l10n.cursorLabel(s.cursor)),
              Text(l10n.pendingLabel(s.pendingCount)),
              if (s.remoteBookId != null)
                Text(l10n.remoteBookLabel(s.remoteBookId!)),
              if (s.lastError != null) Text(l10n.errorLabel(s.lastError!)),
              if (!isLocal) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final sync = ref.read(syncServiceProvider);
                    final result = await sync.syncNow();
                    ref.invalidate(syncStatusProvider);
                    ref.invalidate(transactionListProvider);
                    ref.invalidate(categoryAccountsProvider('expense'));
                    ref.invalidate(categoryAccountsProvider('income'));
                    ref.invalidate(accountBalancesProvider);
                    ref.invalidate(conflictsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.ok
                                ? l10n.syncSuccess(result.cursor)
                                : l10n.syncFailed(result.message),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(l10n.syncNow),
                ),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
