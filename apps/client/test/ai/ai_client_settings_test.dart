import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/ai/chat_client.dart';

void main() {
  test('settings store keeps the key out of the config copy', () async {
    final store = MemoryAiSettingsStore();
    final controller = AiSettingsController(store: store);
    await controller.load();
    expect(controller.settings.isConfigured, isFalse);

    await controller.save(
      const AiSettings(
        apiKey: ' sk-test ',
        baseUrl: 'https://api.deepseek.com/',
        model: 'deepseek-v4-flash',
        autoGenerate: false,
      ),
    );
    expect(store.value.apiKey, 'sk-test');
    expect(store.value.baseUrl, 'https://api.deepseek.com');
    expect(store.value.autoGenerate, isFalse);
    expect(AiSettings.validateBaseUrl('not-a-url'), isNotNull);
    expect(AiSettings.validateBaseUrl('https://api.deepseek.com'), isNull);
  });

  test('deepseek requests disable thinking and map 401', () async {
    Map<String, dynamic>? body;
    String? path;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.uri.path;
          body = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'choices': [
                  {
                    'message': {
                      'content':
                          '{"headline":"ok","highlights":[],"advice":[]}',
                    },
                  },
                ],
                'usage': {'prompt_tokens': 9, 'completion_tokens': 4},
              },
            ),
          );
        },
      ),
    );

    final client = DeepSeekChatClient(dio: dio);
    const settings = AiSettings(
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      autoGenerate: true,
    );
    final result = await client.complete(
      const AiChatRequest(
        settings: settings,
        systemPrompt: 'sys',
        userPrompt: 'user',
      ),
    );

    expect(path, '/chat/completions');
    expect(body?['model'], 'deepseek-v4-flash');
    expect(body?['thinking'], {'type': 'disabled'});
    expect(result.promptTokens, 9);
    expect(result.completionTokens, 4);

    final other = Dio();
    other.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          body = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'choices': [
                  {
                    'message': {'content': '{"headline":"ok"}'},
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    await DeepSeekChatClient(dio: other).complete(
      const AiChatRequest(
        settings: AiSettings(
          apiKey: 'sk-test',
          baseUrl: 'https://compatible.example',
          model: 'gpt-like',
          autoGenerate: true,
        ),
        systemPrompt: 'sys',
        userPrompt: 'user',
      ),
    );
    expect(body!.containsKey('thinking'), isFalse);
  });

  test('ping uses /models and maps unauthorized keys', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    expect(
      () => DeepSeekChatClient(dio: dio).ping(
        const AiSettings(
          apiKey: 'bad',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-v4-flash',
          autoGenerate: true,
        ),
      ),
      throwsA(
        isA<AiChatException>().having(
          (error) => error.message,
          'message',
          contains('API Key 无效'),
        ),
      ),
    );
  });
}
