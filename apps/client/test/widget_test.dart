import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/presentation/pages/settings_page.dart';

void main() {
  testWidgets('renders settings navigation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsPage()),
    );

    expect(find.text('同步中心'), findsOneWidget);
    expect(find.text('冲突处理'), findsOneWidget);
  });
}
