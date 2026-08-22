import '../l10n/l10n.dart';

enum InsightKind { daily, monthly }

enum AiInsightStatus { unconfigured, empty, ready, error }

enum AiProviderKind {
  deepseek,
  opencode,
  custom;

  String get label => switch (this) {
        deepseek => 'DeepSeek',
        opencode => 'OpenCode',
        custom => L10n.current.aiProviderCustom,
      };

  String get defaultBaseUrl => switch (this) {
        deepseek => 'https://api.deepseek.com',
        opencode => 'https://opencode.ai/zen/go/v1',
        custom => '',
      };

  /// Models that speak OpenAI Chat Completions. GPT/Claude on OpenCode Zen
  /// use other protocols and are left out of this preset list.
  List<String> get presetModels => switch (this) {
        deepseek => const ['deepseek-v4-flash', 'deepseek-v4-pro'],
        opencode => const [
            'deepseek-v4-flash',
            'deepseek-v4-pro',
            'glm-5.2',
            'minimax-m2.5',
            'kimi-k2.5',
            'big-pickle',
          ],
        custom => const [],
      };

  String get usageHint => switch (this) {
        deepseek => L10n.current.aiUsageHintDeepseek,
        opencode => L10n.current.aiUsageHintOpencode,
        custom => L10n.current.aiUsageHintCustom,
      };

  static AiProviderKind? tryParse(String? raw) {
    for (final kind in AiProviderKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }

  static AiProviderKind infer({required String baseUrl}) {
    final value = baseUrl.trim().toLowerCase();
    if (value.contains('opencode.ai')) return opencode;
    if (value.contains('deepseek') || value.isEmpty) return deepseek;
    return custom;
  }
}

class AiSettings {
  const AiSettings({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.autoGenerate,
    this.provider = AiProviderKind.deepseek,
  });

  static const defaultBaseUrl = 'https://api.deepseek.com';
  static const defaultModel = 'deepseek-v4-flash';
  static const promptVersion = 'spend-insight.v1';

  static const unset = AiSettings(
    apiKey: '',
    baseUrl: defaultBaseUrl,
    model: defaultModel,
    autoGenerate: true,
    provider: AiProviderKind.deepseek,
  );

  final String apiKey;
  final String baseUrl;
  final String model;
  final bool autoGenerate;
  final AiProviderKind provider;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  List<String> get presetModels => provider.presetModels;

  bool get usesDeepSeekThinking {
    final host = origin.host.toLowerCase();
    return host == 'api.deepseek.com' || host.endsWith('.deepseek.com');
  }

  Uri get origin {
    return Uri.parse(normalizedBaseUrl);
  }

  String get fallbackBaseUrl {
    final fallback = provider.defaultBaseUrl;
    return fallback.isEmpty ? defaultBaseUrl : fallback;
  }

  String get normalizedBaseUrl {
    final value = baseUrl.trim();
    if (value.isEmpty) return fallbackBaseUrl;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String? validateBaseUrl(
    String raw, {
    AiProviderKind provider = AiProviderKind.deepseek,
  }) {
    final fallback = provider.defaultBaseUrl.isEmpty
        ? defaultBaseUrl
        : provider.defaultBaseUrl;
    final value = raw.trim().isEmpty
        ? (provider == AiProviderKind.custom ? '' : fallback)
        : raw.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return L10n.current.invalidHttpUrl;
    }
    if (uri.userInfo.isNotEmpty) {
      return L10n.current.urlMustNotIncludeCredentials;
    }
    return null;
  }

  AiSettings withProvider(AiProviderKind next) {
    if (next == provider) return this;
    final nextUrl =
        next == AiProviderKind.custom ? normalizedBaseUrl : next.defaultBaseUrl;
    final nextModel = next.presetModels.contains(model)
        ? model
        : (next.presetModels.isNotEmpty ? next.presetModels.first : model);
    return copyWith(provider: next, baseUrl: nextUrl, model: nextModel);
  }

  AiSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? autoGenerate,
    AiProviderKind? provider,
  }) {
    return AiSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      autoGenerate: autoGenerate ?? this.autoGenerate,
      provider: provider ?? this.provider,
    );
  }
}

class AiChatRequest {
  const AiChatRequest({
    required this.settings,
    required this.systemPrompt,
    required this.userPrompt,
  });

  final AiSettings settings;
  final String systemPrompt;
  final String userPrompt;
}

class AiChatResult {
  const AiChatResult({
    required this.text,
    this.promptTokens,
    this.completionTokens,
  });

  final String text;
  final int? promptTokens;
  final int? completionTokens;
}

class AiInsightContent {
  const AiInsightContent({
    required this.headline,
    required this.highlights,
    required this.advice,
  });

  final String headline;
  final List<String> highlights;
  final List<String> advice;
}

class AiInsightView {
  const AiInsightView({
    required this.status,
    required this.kind,
    this.periodKey,
    this.periodLabel,
    this.headline,
    this.highlights = const [],
    this.advice = const [],
    this.errorMessage,
    this.model,
    this.promptTokens,
    this.completionTokens,
    this.generatedAt,
    this.stale = false,
  });

  const AiInsightView.unconfigured({required InsightKind kind})
      : this(status: AiInsightStatus.unconfigured, kind: kind);

  final AiInsightStatus status;
  final InsightKind kind;
  final String? periodKey;
  final String? periodLabel;
  final String? headline;
  final List<String> highlights;
  final List<String> advice;
  final String? errorMessage;
  final String? model;
  final int? promptTokens;
  final int? completionTokens;
  final DateTime? generatedAt;
  final bool stale;

  bool get canGenerate => status != AiInsightStatus.unconfigured;
}
