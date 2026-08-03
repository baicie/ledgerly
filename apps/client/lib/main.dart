import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/home_page.dart';
import 'presentation/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LedgerlyApp()));
}

class LedgerlyApp extends StatelessWidget {
  const LedgerlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ledgerly',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F5B)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// Test helper entry that injects an in-memory database.
class LedgerlyTestApp extends ConsumerWidget {
  const LedgerlyTestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const LedgerlyApp();
  }
}
