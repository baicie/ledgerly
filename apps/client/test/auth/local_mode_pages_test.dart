import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/presentation/pages/feed_page.dart';
import 'package:ledgerly_client/presentation/pages/reports_page.dart';
import 'package:ledgerly_client/presentation/pages/sync_center_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';

void main() {
  testWidgets('local feed does not open remote transaction revisions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiEndpointProvider.overrideWithValue(null),
          monthTransactionsProvider.overrideWith(
            (ref) async => [
              TransactionSummary(
                id: 'tx-1',
                occurredAt: DateTime.utc(2026, 8, 4),
                description: '午餐',
                entryCount: 2,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: FeedPage()),
      ),
    );
    await tester.pumpAndSettle();

    final transactionTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('午餐'),
        matching: find.byType(ListTile),
      ),
    );
    expect(transactionTile.onTap, isNull);
  });

  testWidgets('local reports never read the remote API provider',
      (tester) async {
    var remoteApiRead = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiEndpointProvider.overrideWithValue(null),
          categoryReportProvider.overrideWith((ref) async => []),
          syncApiProvider.overrideWith((ref) {
            remoteApiRead = true;
            throw StateError('remote API must stay inactive');
          }),
        ],
        child: const MaterialApp(home: ReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(remoteApiRead, isFalse);
    expect(find.textContaining('本地 ·'), findsOneWidget);
    expect(find.text('服务端汇总（plus）'), findsNothing);
  });

  testWidgets('local sync center never exposes or reads remote sync',
      (tester) async {
    var remoteSyncRead = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiEndpointProvider.overrideWithValue(null),
          syncStatusProvider.overrideWith(
            (ref) async => SyncStatusView(
              label: '就绪',
              cursor: 0,
              pendingCount: 2,
            ),
          ),
          syncServiceProvider.overrideWith((ref) {
            remoteSyncRead = true;
            throw StateError('remote sync must stay inactive');
          }),
        ],
        child: const MaterialApp(home: SyncCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(remoteSyncRead, isFalse);
    expect(find.text('仅本地存储'), findsOneWidget);
    expect(find.text('立即同步'), findsNothing);
    expect(find.text('待推送：2'), findsOneWidget);
  });
}
