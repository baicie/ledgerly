import 'package:flutter/material.dart';

import '../config/api_endpoint_controller.dart';
import '../config/api_endpoint_messages.dart';
import '../l10n/l10n.dart';

Future<String?> showApiEndpointEditorDialog({
  required BuildContext context,
  required ApiEndpointController controller,
  required String currentValue,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _ApiEndpointEditorDialog(
      controller: controller,
      currentValue: currentValue,
    ),
  );
}

class _ApiEndpointEditorDialog extends StatefulWidget {
  const _ApiEndpointEditorDialog({
    required this.controller,
    required this.currentValue,
  });

  final ApiEndpointController controller;
  final String currentValue;

  @override
  State<_ApiEndpointEditorDialog> createState() =>
      _ApiEndpointEditorDialogState();
}

class _ApiEndpointEditorDialogState extends State<_ApiEndpointEditorDialog> {
  late final TextEditingController _inputController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final endpoint = widget.controller.validate(_inputController.text);
      Navigator.pop(context, endpoint?.baseUrl ?? '');
    } catch (error) {
      setState(() => _errorText = apiEndpointErrorText(error, l10nOf(context)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10nOf(context).apiService),
      content: SizedBox(
        width: 440,
        child: TextField(
          key: const Key('api-endpoint-input'),
          controller: _inputController,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10nOf(context).apiAddressOptional,
            hintText: '192.168.1.10:8080',
            helperText: l10nOf(context).apiAddressHelper,
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.dns_outlined),
            border: const OutlineInputBorder(),
            errorText: _errorText,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10nOf(context).cancel),
        ),
        FilledButton.icon(
          key: const Key('api-endpoint-save'),
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: Text(l10nOf(context).confirm),
        ),
      ],
    );
  }
}
