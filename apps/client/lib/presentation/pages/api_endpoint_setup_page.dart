import 'package:flutter/material.dart';

import '../../config/api_endpoint_controller.dart';
import '../api_endpoint_editor.dart';

class ApiEndpointSetupPage extends StatefulWidget {
  const ApiEndpointSetupPage({super.key, required this.controller});

  final ApiEndpointController controller;

  @override
  State<ApiEndpointSetupPage> createState() => _ApiEndpointSetupPageState();
}

class _ApiEndpointSetupPageState extends State<ApiEndpointSetupPage> {
  final _inputController = TextEditingController();
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final message = widget.controller.state.message;
    if (message != null) {
      _errorText = message.startsWith('无法')
          ? message
          : apiEndpointErrorText(FormatException(message));
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.controller.save(_inputController.text);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _errorText = apiEndpointErrorText(error));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'API 地址保存失败，请稍后重试。');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: SizedBox(
                    width: 460,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Ledgerly',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'API 服务配置',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '地址选填，留空时仅在本机存储',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          key: const Key('api-endpoint-input'),
                          controller: _inputController,
                          autofocus: true,
                          enabled: !_saving,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _save(),
                          decoration: InputDecoration(
                            labelText: 'API 地址（选填）',
                            hintText: 'https://your-server.example',
                            prefixIcon: const Icon(Icons.dns_outlined),
                            border: const OutlineInputBorder(),
                            errorText: _errorText,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const Key('api-endpoint-save'),
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          label: const Text('保存设置'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
