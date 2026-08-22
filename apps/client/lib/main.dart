import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/api_endpoint.dart';
import 'config/api_endpoint_controller.dart';
import 'config/platform_api_endpoint_store.dart';
import 'l10n/l10n.dart';
import 'presentation/ai_providers.dart';
import 'presentation/design/ledgerly_theme.dart';
import 'presentation/pages/api_endpoint_setup_page.dart';
import 'presentation/providers.dart';
import 'routing/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    LedgerlyBootstrap(
      controller: ApiEndpointController(
        store: createPlatformApiEndpointStore(),
        buildDefault: ApiEndpoint.environmentDefault,
        isRelease: kReleaseMode,
        isWeb: kIsWeb,
      ),
    ),
  );
}

class LedgerlyBootstrap extends StatefulWidget {
  const LedgerlyBootstrap({
    super.key,
    required this.controller,
    this.application = const LedgerlyApp(),
  });

  final ApiEndpointController controller;

  @visibleForTesting
  final Widget application;

  @override
  State<LedgerlyBootstrap> createState() => _LedgerlyBootstrapState();
}

class _LedgerlyBootstrapState extends State<LedgerlyBootstrap> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final endpoint = state.endpoint;
        if (state.status == ApiEndpointStatus.loading) {
          return const _EndpointLoadingApp();
        }
        if (state.status == ApiEndpointStatus.needsConfiguration) {
          return MaterialApp(
            title: 'Ledgerly',
            debugShowCheckedModeBanner: false,
            theme: ledgerlyTheme(),
            localeResolutionCallback: L10n.resolve,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ApiEndpointSetupPage(controller: widget.controller),
          );
        }
        return ProviderScope(
          key: ValueKey(endpoint?.baseUrl ?? 'local'),
          overrides: [
            apiEndpointProvider.overrideWithValue(endpoint),
            apiEndpointControllerProvider.overrideWithValue(widget.controller),
          ],
          child: widget.application,
        );
      },
    );
  }
}

class LedgerlyApp extends ConsumerStatefulWidget {
  const LedgerlyApp({super.key});

  @override
  ConsumerState<LedgerlyApp> createState() => _LedgerlyAppState();
}

class _LedgerlyAppState extends ConsumerState<LedgerlyApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = createAppRouter(
      ref.read(authControllerProvider),
      ref.read(apiEndpointControllerProvider),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(aiInsightBootstrapProvider);
    ref.invalidate(todayAiInsightProvider);
    ref.invalidate(selectedMonthAiInsightProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ledgerly',
      debugShowCheckedModeBanner: false,
      theme: ledgerlyTheme(),
      localeResolutionCallback: L10n.resolve,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}

class _EndpointLoadingApp extends StatelessWidget {
  const _EndpointLoadingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ledgerly',
      debugShowCheckedModeBanner: false,
      theme: ledgerlyTheme(),
      localeResolutionCallback: L10n.resolve,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('api-endpoint-loading')),
        ),
      ),
    );
  }
}
