import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledgerly_client/main.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:drift/native.dart';

void main() {
  testWidgets('renders the Ledgerly shell', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const LedgerlyApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
