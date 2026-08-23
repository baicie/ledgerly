import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_models.dart';
import '../../l10n/l10n.dart';
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
  final _customPromptController = TextEditingController();
  var _provider = AiProviderKind.deepseek;
  var _promptPreset = AiPromptPreset.balanced;
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
    _customPromptController.dispose();
    super.dispose();
  }

  void _hydrate(AiSettings settings) {
    if (_loaded) return;
    _keyController.text = settings.apiKey;
    _baseUrlController.text = settings.baseUrl;
    _modelController.text = settings.model;
    _customPromptController.text = settings.customSystemPrompt;
    _provider = settings.provider;
    _promptPreset = settings.promptPreset;
    _autoGenerate = settings.autoGenerate;
    _loaded = true;
  }

  AiSettings _draft() {
    return AiSettings(
      apiKey: _keyController.text,
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
      autoGenerate: _autoGenerate,
      provider: _provider,
      promptPreset: _promptPreset,
      customSystemPrompt: _customPromptController.text,
    );
  }

  void _selectProvider(AiProviderKind? value) {
    if (value == null) return;
    final next = _draft().withProvider(value);
    setState(() {
      _provider = next.provider;
      _baseUrlController.text = next.baseUrl;
      _modelController.text = next.model;
    });
  }

  Future<void> _save() async {
    final urlError = AiSettings.validateBaseUrl(
      _baseUrlController.text,
      provider: _provider,
    );
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
        _message = l10nOf(context).aiSavedLocally;
        _messageError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = l10nOf(context).saveFailed('$error');
        _messageError = true;
      });
    }
  }

  Future<void> _test() async {
    final urlError = AiSettings.validateBaseUrl(
      _baseUrlController.text,
      provider: _provider,
    );
    if (urlError != null) {
      setState(() {
        _message = urlError;
        _messageError = true;
      });
      return;
    }
    if (_keyController.text.trim().isEmpty) {
      setState(() {
        _message = l10nOf(context).enterApiKeyFirst;
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
        _message = l10nOf(context).connectionSuccess;
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
    final presets = _provider.presetModels;
    final usingCustomModel = !presets.contains(_modelController.text);

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).aiSettingsTitle)),
      body: SafeArea(
        top: false,
        child: LedgerlyContent(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              sliver: SliverToBoxAdapter(
                child: LedgerlySection(
                  title: l10nOf(context).modelService,
                  child: Column(
                    children: [
                      DropdownButtonFormField<AiProviderKind>(
                        key: Key('ai-settings-provider-${_provider.name}'),
                        initialValue: _provider,
                        decoration: InputDecoration(
                            labelText: l10nOf(context).provider),
                        items: [
                          for (final kind in AiProviderKind.values)
                            DropdownMenuItem(
                              value: kind,
                              child: Text(kind.label),
                            ),
                        ],
                        onChanged: _selectProvider,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('ai-settings-api-key'),
                        controller: _keyController,
                        obscureText: _obscureKey,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-...',
                          suffixIcon: IconButton(
                            tooltip: _obscureKey
                                ? l10nOf(context).show
                                : l10nOf(context).hide,
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
                        decoration: InputDecoration(
                          labelText: 'Base URL',
                          hintText: _provider.defaultBaseUrl.isEmpty
                              ? 'https://api.example.com/v1'
                              : _provider.defaultBaseUrl,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: Key(
                          'ai-settings-model-preset-${_provider.name}-${_modelController.text}',
                        ),
                        initialValue:
                            usingCustomModel ? 'custom' : _modelController.text,
                        decoration:
                            InputDecoration(labelText: l10nOf(context).model),
                        items: [
                          for (final model in presets)
                            DropdownMenuItem(value: model, child: Text(model)),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text(l10nOf(context).custom),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            if (value == 'custom') {
                              if (presets.contains(_modelController.text)) {
                                _modelController.text = '';
                              }
                            } else {
                              _modelController.text = value;
                            }
                          });
                        },
                      ),
                      if (usingCustomModel) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('ai-settings-model-custom'),
                          controller: _modelController,
                          decoration: InputDecoration(
                            labelText: l10nOf(context).customModelId,
                            hintText: AiSettings.defaultModel,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AiPromptPreset>(
                        key: Key(
                          'ai-settings-prompt-preset-${_promptPreset.name}',
                        ),
                        initialValue: _promptPreset,
                        decoration: InputDecoration(
                          labelText: l10nOf(context).aiPromptPreset,
                        ),
                        items: [
                          for (final preset in AiPromptPreset.values)
                            DropdownMenuItem(
                              value: preset,
                              child: Text(preset.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _promptPreset = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _promptPreset.subtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (_promptPreset == AiPromptPreset.custom) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('ai-settings-custom-prompt'),
                          controller: _customPromptController,
                          minLines: 4,
                          maxLines: 8,
                          decoration: InputDecoration(
                            labelText: l10nOf(context).aiCustomSystemPrompt,
                            hintText: l10nOf(context).aiCustomSystemPromptHint,
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                      SwitchListTile(
                        key: const Key('ai-settings-auto-generate'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10nOf(context).autoGenerateInsights),
                        subtitle:
                            Text(l10nOf(context).autoGenerateInsightsSubtitle),
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
                              child: Text(
                                _testing
                                    ? l10nOf(context).testingConnection
                                    : l10nOf(context).testConnection,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              key: const Key('ai-settings-save'),
                              onPressed: _saving || _testing ? null : _save,
                              child: Text(
                                _saving
                                    ? l10nOf(context).savingEllipsis
                                    : l10nOf(context).save,
                              ),
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
                  title: l10nOf(context).capabilitiesAndUsage,
                  child: Text(
                    _capabilityCopy(),
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

  String _capabilityCopy() {
    final l10n = L10n.current;
    final opencode =
        _provider == AiProviderKind.opencode ? l10n.aiCapabilityOpencode : '';
    return '${l10n.aiCapabilityProtocol}$opencode\n${l10n.aiCapabilityUsage(_provider.usageHint)}';
  }
}
