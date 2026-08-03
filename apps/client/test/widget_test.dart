import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledgerly_client/main.dart';

void main() {
  testWidgets('renders the Ledgerly shell', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: LedgerlyApp()),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
