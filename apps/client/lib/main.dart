import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/api_endpoint.dart';
import 'presentation/providers.dart';
import 'routing/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final endpoint = ApiEndpoint.fromEnvironment();
    runApp(
      ProviderScope(
        overrides: [apiEndpointProvider.overrideWithValue(endpoint)],
        child: const LedgerlyApp(),
      ),
    );
  } on FormatException catch (error) {
    runApp(ConfigurationErrorApp(message: error.message));
  }
}

class LedgerlyApp extends ConsumerStatefulWidget {
  const LedgerlyApp({super.key});

  @override
  ConsumerState<LedgerlyApp> createState() => _LedgerlyAppState();
}

class _LedgerlyAppState extends ConsumerState<LedgerlyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(ref.read(authControllerProvider));
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ledgerly',
      theme: ledgerlyTheme(),
      routerConfig: _router,
    );
  }
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ledgerly',
      theme: ledgerlyTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings_ethernet, size: 46),
                    const SizedBox(height: 16),
                    Text(
                      'API 配置无效',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData ledgerlyTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F6F5B),
      brightness: Brightness.light,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF7F8F7),
    ),
    useMaterial3: true,
  );
}
