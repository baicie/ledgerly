import 'package:flutter/material.dart';

import '../config/api_endpoint_controller.dart';

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
      setState(() => _errorText = apiEndpointErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('API 服务'),
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
            labelText: 'API 地址（选填）',
            hintText: 'https://your-server.example',
            helperText: '留空后仅使用本地存储',
            prefixIcon: const Icon(Icons.dns_outlined),
            border: const OutlineInputBorder(),
            errorText: _errorText,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const Key('api-endpoint-save'),
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('确认'),
        ),
      ],
    );
  }
}

String apiEndpointErrorText(Object error) {
  if (error is FormatException) {
    final message = error.message;
    if (message.contains('Release builds require')) {
      return '正式版本仅支持非本机 HTTPS 地址';
    }
    if (message.contains('default HTTPS port')) {
      return 'Web 正式版本仅支持 HTTPS 默认端口（443）';
    }
    if (message.contains('origin without')) {
      return '请输入不含路径、查询或凭据的 API 根地址';
    }
    if (message.contains('required')) {
      return '请输入 API 地址';
    }
  }
  return '请输入有效的 HTTP(S) API 地址';
}
