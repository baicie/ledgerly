import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'ai_models.dart';

abstract interface class AiChatClient {
  Future<AiChatResult> complete(AiChatRequest request);

  Future<void> ping(AiSettings settings);
}

class OpenAiCompatibleChatClient implements AiChatClient {
  OpenAiCompatibleChatClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(connectTimeout: const Duration(seconds: 15)),
            );

  final Dio _dio;

  @override
  Future<AiChatResult> complete(AiChatRequest request) async {
    final settings = request.settings;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${settings.normalizedBaseUrl}${_endpoint(settings.wireProtocol)}',
        data: _requestBody(request, settings.wireProtocol),
        options: _requestOptions(
          headers: _headers(
            settings,
            sessionId: _conversationSessionId(request),
            includeContentType: true,
          ),
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final result = _parseResponse(
        response.data ?? const {},
        settings.wireProtocol,
      );
      final text = result.text.trim();
      if (text.trim().isEmpty) {
        throw AiChatException(L10n.current.modelReturnedEmpty);
      }
      return result;
    } on AiChatException {
      rethrow;
    } on DioException catch (error) {
      throw AiChatException(
        describeAiError(error),
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<void> ping(AiSettings settings) async {
    try {
      await _dio.get<dynamic>(
        '${settings.normalizedBaseUrl}/models',
        options: _requestOptions(
          headers: _headers(
            settings,
            sessionId:
                'ledgerly-${fnv1aHex('${settings.provider.name}:${settings.model}:ping')}',
            includeContentType: false,
          ),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
    } on DioException catch (error) {
      throw AiChatException(
        describeAiError(error),
        statusCode: error.response?.statusCode,
      );
    }
  }
}

const _userAgent = 'ledgerly-client/0.1.0';

String _endpoint(AiWireProtocol protocol) {
  return switch (protocol) {
    AiWireProtocol.chatCompletions => '/chat/completions',
    AiWireProtocol.messages => '/messages',
    AiWireProtocol.responses => '/responses',
  };
}

Map<String, dynamic> _requestBody(
  AiChatRequest request,
  AiWireProtocol protocol,
) {
  final settings = request.settings;
  final selectedModel = settings.model.trim().isEmpty
      ? AiSettings.defaultModel
      : settings.model.trim();
  return switch (protocol) {
    AiWireProtocol.chatCompletions => {
        'model': selectedModel,
        'messages': [
          {'role': 'system', 'content': request.systemPrompt},
          {'role': 'user', 'content': request.userPrompt},
        ],
        'stream': false,
        'max_tokens': 800,
        'temperature': 0.3,
        if (settings.usesDeepSeekThinking)
          'thinking': const {'type': 'disabled'},
      },
    AiWireProtocol.messages => {
        'model': selectedModel,
        'system': request.systemPrompt,
        'messages': [
          {'role': 'user', 'content': request.userPrompt},
        ],
        'max_tokens': 800,
        'temperature': 0.3,
      },
    AiWireProtocol.responses => {
        'model': selectedModel,
        'instructions': request.systemPrompt,
        'input': request.userPrompt,
        'max_output_tokens': 800,
        'temperature': 0.3,
      },
  };
}

Map<String, String> _headers(
  AiSettings settings, {
  required String sessionId,
  required bool includeContentType,
}) {
  return {
    'Authorization': 'Bearer ${settings.apiKey.trim()}',
    if (!kIsWeb) 'User-Agent': _userAgent,
    if (includeContentType) 'Content-Type': 'application/json',
    if (settings.usesOpenCode) 'x-opencode-session': sessionId,
  };
}

String _conversationSessionId(AiChatRequest request) {
  final explicit = request.sessionId?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final fingerprint = [
    request.settings.provider.name,
    request.settings.model.trim(),
    request.systemPrompt,
    request.userPrompt,
  ].join('\n');
  return 'ledgerly-${fnv1aHex(fingerprint)}';
}

AiChatResult _parseResponse(
  Map<String, dynamic> data,
  AiWireProtocol protocol,
) {
  final usage = data['usage'];
  final promptTokens = usage is Map
      ? _asInt(usage['prompt_tokens'] ?? usage['input_tokens'])
      : null;
  final completionTokens = usage is Map
      ? _asInt(usage['completion_tokens'] ?? usage['output_tokens'])
      : null;
  final text = switch (protocol) {
    AiWireProtocol.chatCompletions => _chatCompletionsText(data),
    AiWireProtocol.messages => _contentText(data['content']),
    AiWireProtocol.responses => _responsesText(data),
  };
  return AiChatResult(
    text: text,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
  );
}

String _chatCompletionsText(Map<String, dynamic> data) {
  final choices = data['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
  final message = Map<String, dynamic>.from(choices.first as Map)['message'];
  if (message is! Map) return '';
  return message['content']?.toString() ?? '';
}

String _responsesText(Map<String, dynamic> data) {
  final outputText = data['output_text'];
  if (outputText is String && outputText.trim().isNotEmpty) return outputText;
  final output = data['output'];
  if (output is! List) return '';
  return output
      .whereType<Map>()
      .expand((item) =>
          item['content'] is List ? item['content'] as List : const [])
      .whereType<Map>()
      .map((part) => part['text']?.toString() ?? '')
      .join();
}

String _contentText(Object? content) {
  if (content is String) return content;
  if (content is! List) return '';
  return content
      .whereType<Map>()
      .map((part) => part['text']?.toString() ?? '')
      .join();
}

Options _requestOptions({
  required Map<String, String> headers,
  required Duration receiveTimeout,
  Duration? sendTimeout,
}) {
  return Options(
    headers: headers,
    // Dio web forbids sendTimeout unless the request has a body.
    sendTimeout: kIsWeb ? null : sendTimeout,
    receiveTimeout: receiveTimeout,
  );
}

class AiChatException implements Exception {
  const AiChatException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

String describeAiError(DioException error) {
  final l10n = L10n.current;
  final status = error.response?.statusCode;
  if (status == 401) return l10n.invalidApiKey;
  if (status == 402) return l10n.modelBalanceLow;
  if (status == 429) return l10n.tooManyRequests;
  if (_looksLikeCors(error)) {
    return l10n.corsBlockedOpencode;
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.unknown) {
    return kIsWeb ? l10n.cannotReachModelWeb : l10n.cannotReachModel;
  }
  if (error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.connectionTimeout) {
    return l10n.modelTimeout;
  }
  return status == null
      ? l10n.modelCallFailed
      : l10n.modelCallFailedWithStatus(status);
}

bool _looksLikeCors(DioException error) {
  final text = '${error.message} ${error.error}'.toLowerCase();
  return text.contains('cors') ||
      text.contains('xmlhttprequest') ||
      text.contains('access-control-allow-origin');
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

class FakeAiChatClient implements AiChatClient {
  FakeAiChatClient({this.completeHandler, this.pingHandler});

  Future<AiChatResult> Function(AiChatRequest request)? completeHandler;
  Future<void> Function(AiSettings settings)? pingHandler;
  final requests = <AiChatRequest>[];
  var pingCount = 0;

  @override
  Future<AiChatResult> complete(AiChatRequest request) async {
    requests.add(request);
    if (completeHandler != null) return completeHandler!(request);
    return const AiChatResult(
      text:
          '{"headline":"餐饮占比较高","highlights":["午餐支出明显"],"advice":["可考虑减少外卖"]}',
      promptTokens: 12,
      completionTokens: 24,
    );
  }

  @override
  Future<void> ping(AiSettings settings) async {
    pingCount += 1;
    if (pingHandler != null) return pingHandler!(settings);
  }
}
