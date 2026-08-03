import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';

class StartupPage extends StatelessWidget {
  const StartupPage({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final failure = controller.state.status == AuthStatus.failure;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        failure
                            ? Icons.cloud_off_outlined
                            : Icons.account_balance_wallet_outlined,
                        size: 46,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ledgerly',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      if (failure) ...[
                        Text(
                          controller.state.message ?? '会话恢复失败。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: controller.restore,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ] else
                        const CircularProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
