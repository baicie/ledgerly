import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
        throw const AiChatException('模型没有返回可用内容。');
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
  final status = error.response?.statusCode;
  if (status == 401) return 'API Key 无效，请检查设置。';
  if (status == 402) return '模型账户余额不足。';
  if (status == 429) return '请求过于频繁，请稍后再试。';
  if (_looksLikeCors(error)) {
    return '浏览器拦截了跨域请求。OpenCode 官方接口不允许网页直连，请保存后在 App 中使用，或改用带 CORS 的兼容网关。';
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.unknown) {
    return kIsWeb
        ? '无法连接模型服务。网页端可能被跨域拦截，请改用 App 或兼容端点。'
        : '无法连接模型服务，请检查网络和 Base URL。';
  }
  if (error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.connectionTimeout) {
    return '模型服务超时，请稍后重试。';
  }
  return '模型调用失败${status == null ? '' : '（$status）'}。';
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
