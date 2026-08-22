import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_models.dart';
import '../ai_providers.dart';
import '../design/ledgerly_theme.dart';
import '../widgets/ledgerly_layout.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  var _autoGenerate = true;
  var _obscureKey = true;
  var _saving = false;
  var _testing = false;
  var _loaded = false;
  String? _message;
  bool? _messageError;

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _hydrate(AiSettings settings) {
    if (_loaded) return;
    _keyController.text = settings.apiKey;
    _baseUrlController.text = settings.baseUrl;
    _modelController.text = settings.model;
    _autoGenerate = settings.autoGenerate;
    _loaded = true;
  }

  AiSettings _draft() {
    return AiSettings(
      apiKey: _keyController.text,
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
      autoGenerate: _autoGenerate,
    );
  }

  Future<void> _save() async {
    final urlError = AiSettings.validateBaseUrl(_baseUrlController.text);
    if (urlError != null) {
      setState(() {
        _message = urlError;
        _messageError = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(aiSettingsControllerProvider).save(_draft());
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = '已保存。密钥只留在本机，不会同步到账本服务。';
        _messageError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = '保存失败：$error';
        _messageError = true;
      });
    }
  }

  Future<void> _test() async {
    final urlError = AiSettings.validateBaseUrl(_baseUrlController.text);
    if (urlError != null) {
      setState(() {
        _message = urlError;
        _messageError = true;
      });
      return;
    }
    if (_keyController.text.trim().isEmpty) {
      setState(() {
        _message = '请先填写 API Key。';
        _messageError = true;
      });
      return;
    }
    setState(() {
      _testing = true;
      _message = null;
    });
    try {
      await ref.read(aiChatClientProvider).ping(_draft());
      if (!mounted) return;
      setState(() {
        _testing = false;
        _message = '连接成功。';
        _messageError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _message = error.toString();
        _messageError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(aiSettingsControllerProvider);
    if (controller.loaded) {
      _hydrate(controller.settings);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('智能分析')),
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  title: '模型服务',
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('ai-settings-api-key'),
                        controller: _keyController,
                        obscureText: _obscureKey,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-...',
                          suffixIcon: IconButton(
                            tooltip: _obscureKey ? '显示' : '隐藏',
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('ai-settings-base-url'),
                        controller: _baseUrlController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          hintText: AiSettings.defaultBaseUrl,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: Key(
                          'ai-settings-model-preset-${_modelController.text}',
                        ),
                        initialValue:
                            AiSettings.presetModels.contains(
                              _modelController.text,
                            )
                            ? _modelController.text
                            : 'custom',
                        decoration: const InputDecoration(labelText: '模型'),
                        items: [
                          for (final model in AiSettings.presetModels)
                            DropdownMenuItem(value: model, child: Text(model)),
                          const DropdownMenuItem(
                            value: 'custom',
                            child: Text('自定义'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            if (value == 'custom') {
                              if (AiSettings.presetModels.contains(
                                _modelController.text,
                              )) {
                                _modelController.text = '';
                              }
                            } else {
                              _modelController.text = value;
                            }
                          });
                        },
                      ),
                      if (!AiSettings.presetModels.contains(
                        _modelController.text,
                      )) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('ai-settings-model-custom'),
                          controller: _modelController,
                          decoration: const InputDecoration(
                            labelText: '自定义模型 ID',
                            hintText: AiSettings.defaultModel,
                          ),
                        ),
                      ],
                      SwitchListTile(
                        key: const Key('ai-settings-auto-generate'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动生成分析'),
                        subtitle: const Text('打开应用时补齐今日、昨日和上月总结'),
                        value: _autoGenerate,
                        onChanged: (value) =>
                            setState(() => _autoGenerate = value),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('ai-settings-test'),
                              onPressed: _testing || _saving ? null : _test,
                              child: Text(_testing ? '测试中…' : '测试连接'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              key: const Key('ai-settings-save'),
                              onPressed: _saving || _testing ? null : _save,
                              child: Text(_saving ? '保存中…' : '保存'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  title: '能力与用量',
                  child: Text(
                    '默认模型 deepseek-v4-flash 是文本模型，不能语音转文字。'
                    '分析会把分类、金额和备注发送到你配置的端点。\n'
                    '第一期不做累计用量看板，余额请到 DeepSeek 控制台查看；'
                    '分析卡片会显示最近一次调用的 token。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            if (_message != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    _message!,
                    key: const Key('ai-settings-message'),
                    style: TextStyle(
                      color: _messageError == true
                          ? Theme.of(context).colorScheme.error
                          : LedgerlyColors.brand,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
