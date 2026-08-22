enum InsightKind { daily, monthly }

enum AiInsightStatus { unconfigured, empty, ready, error }

class AiSettings {
  const AiSettings({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.autoGenerate,
  });

  static const defaultBaseUrl = 'https://api.deepseek.com';
  static const defaultModel = 'deepseek-v4-flash';
  static const promptVersion = 'spend-insight.v1';
  static const presetModels = ['deepseek-v4-flash', 'deepseek-v4-pro'];

  static const unset = AiSettings(
    apiKey: '',
    baseUrl: defaultBaseUrl,
    model: defaultModel,
    autoGenerate: true,
  );

  final String apiKey;
  final String baseUrl;
  final String model;
  final bool autoGenerate;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  bool get usesDeepSeekThinking {
    final modelName = model.toLowerCase();
    final url = baseUrl.toLowerCase();
    return modelName.contains('deepseek') || url.contains('deepseek');
  }

  Uri get origin {
    return Uri.parse(normalizedBaseUrl);
  }

  String get normalizedBaseUrl {
    final value = baseUrl.trim();
    if (value.isEmpty) return defaultBaseUrl;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String? validateBaseUrl(String raw) {
    final value = raw.trim().isEmpty ? defaultBaseUrl : raw.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return '请输入 http(s) 地址';
    }
    if (uri.userInfo.isNotEmpty) {
      return '地址不能包含账号密码';
    }
    return null;
  }

  AiSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? autoGenerate,
  }) {
    return AiSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      autoGenerate: autoGenerate ?? this.autoGenerate,
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
