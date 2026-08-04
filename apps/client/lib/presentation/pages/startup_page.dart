import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../config/api_endpoint_controller.dart';
import '../api_endpoint_editor.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({
    super.key,
    required this.controller,
    required this.endpointController,
  });

  final AuthController controller;
  final ApiEndpointController endpointController;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  bool _editingEndpoint = false;

  Future<void> _editEndpoint() async {
    final current = widget.endpointController.state.endpoint?.baseUrl;
    if (current == null) return;
    final selected = await showApiEndpointEditorDialog(
      context: context,
      controller: widget.endpointController,
      currentValue: current,
    );
    if (selected == null || selected == current || !mounted) return;

    setState(() => _editingEndpoint = true);
    try {
      await widget.endpointController.save(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 地址保存失败，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _editingEndpoint = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.endpointController,
      ]),
      builder: (context, _) {
        final failure = widget.controller.state.status == AuthStatus.failure;
        final endpoint = widget.endpointController.state.endpoint;
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
                          widget.controller.state.message ?? '会话恢复失败。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.dns_outlined, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                endpoint?.baseUrl ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              key: const Key('startup-api-edit'),
                              tooltip: '更换 API 服务',
                              onPressed:
                                  _editingEndpoint ? null : _editEndpoint,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _editingEndpoint
                              ? null
                              : widget.controller.restore,
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
