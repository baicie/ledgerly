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
        '${settings.normalizedBaseUrl}/chat/completions',
        data: {
          'model': settings.model.trim().isEmpty
              ? AiSettings.defaultModel
              : settings.model.trim(),
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
        options: _requestOptions(
          headers: {
            'Authorization': 'Bearer ${settings.apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final data = response.data ?? const {};
      final choices = data['choices'];
      String text = '';
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first is Map
            ? Map<String, dynamic>.from(choices.first as Map)['message']
            : null;
        if (message is Map) {
          text = message['content']?.toString() ?? '';
        }
      }
      if (text.trim().isEmpty) {
        throw AiChatException(L10n.current.modelReturnedEmpty);
      }
      final usage = data['usage'];
      return AiChatResult(
        text: text,
        promptTokens: usage is Map ? _asInt(usage['prompt_tokens']) : null,
        completionTokens:
            usage is Map ? _asInt(usage['completion_tokens']) : null,
      );
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
          headers: {'Authorization': 'Bearer ${settings.apiKey.trim()}'},
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
