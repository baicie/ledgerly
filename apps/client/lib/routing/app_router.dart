import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../presentation/pages/accounts_page.dart';
import '../presentation/pages/attachments_page.dart';
import '../presentation/pages/auth_page.dart';
import '../presentation/pages/budgets_page.dart';
import '../presentation/pages/conflicts_page.dart';
import '../presentation/pages/export_page.dart';
import '../presentation/pages/family_invite_page.dart';
import '../presentation/pages/feed_page.dart';
import '../presentation/pages/fx_rates_page.dart';
import '../presentation/pages/recurring_page.dart';
import '../presentation/pages/reports_page.dart';
import '../presentation/pages/settings_page.dart';
import '../presentation/pages/shell_page.dart';
import '../presentation/pages/startup_page.dart';
import '../presentation/pages/subscription_page.dart';
import '../presentation/pages/sync_center_page.dart';
import '../presentation/pages/transaction_revisions_page.dart';

String? authRedirect(AuthState auth, String location) {
  if (auth.status == AuthStatus.restoring ||
      auth.status == AuthStatus.failure) {
    return location == '/startup' ? null : '/startup';
  }
  if (auth.status != AuthStatus.authenticated) {
    return location == '/auth' ? null : '/auth';
  }
  if (location == '/auth' || location == '/startup') {
    return '/feed';
  }
  return null;
}

GoRouter createAppRouter(AuthController controller) {
  return GoRouter(
    initialLocation: '/startup',
    refreshListenable: controller,
    redirect: (context, state) {
      return authRedirect(controller.state, state.matchedLocation);
    },
    routes: [
      GoRoute(
        path: '/startup',
        builder: (context, state) => StartupPage(controller: controller),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthPage(controller: controller),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellPage(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                builder: (context, state) => const FeedPage(),
                routes: [
                  GoRoute(
                    path: 'revisions/:txId',
                    builder: (context, state) => TransactionRevisionsPage(
                      transactionId: state.pathParameters['txId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accounts',
                builder: (context, state) => const AccountsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'sync',
                    builder: (context, state) => const SyncCenterPage(),
                  ),
                  GoRoute(
                    path: 'conflicts',
                    builder: (context, state) => const ConflictsPage(),
                  ),
                  GoRoute(
                    path: 'export',
                    builder: (context, state) => const ExportPage(),
                  ),
                  GoRoute(
                    path: 'subscription',
                    builder: (context, state) => const SubscriptionPage(),
                  ),
                  GoRoute(
                    path: 'fx',
                    builder: (context, state) => const FxRatesPage(),
                  ),
                  GoRoute(
                    path: 'family',
                    builder: (context, state) => const FamilyInvitePage(),
                  ),
                  GoRoute(
                    path: 'budgets',
                    builder: (context, state) => const BudgetsPage(),
                  ),
                  GoRoute(
                    path: 'recurring',
                    builder: (context, state) => const RecurringPage(),
                  ),
                  GoRoute(
                    path: 'attachments',
                    builder: (context, state) => const AttachmentsPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
