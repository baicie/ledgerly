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
    expect(store.value.provider, AiProviderKind.deepseek);
    expect(store.value.promptPreset, AiPromptPreset.balanced);
    expect(AiSettings.validateBaseUrl('not-a-url'), isNotNull);
    expect(AiSettings.validateBaseUrl('https://api.deepseek.com'), isNull);
    expect(
      AiSettings.validateBaseUrl('', provider: AiProviderKind.custom),
      isNotNull,
    );
    expect(
      AiProviderKind.infer(baseUrl: 'https://opencode.ai/zen/go/v1'),
      AiProviderKind.opencode,
    );
    expect(
      AiSettings.unset.withProvider(AiProviderKind.opencode).baseUrl,
      'https://opencode.ai/zen/go/v1',
    );
    expect(
      const AiSettings(
        apiKey: '',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        autoGenerate: true,
      ).withProvider(AiProviderKind.opencode).model,
      'deepseek-v4-flash',
    );
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

    final client = OpenAiCompatibleChatClient(dio: dio);
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
    await OpenAiCompatibleChatClient(dio: other).complete(
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

  test('opencode zen uses v1 chat completions without thinking', () async {
    String? path;
    Map<String, dynamic>? body;
    final headersSeen = <Map<String, String>>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.uri.path;
          body = Map<String, dynamic>.from(options.data as Map);
          headersSeen.add(
            options.headers.map(
              (key, value) => MapEntry(key, value.toString()),
            ),
          );
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

    final client = OpenAiCompatibleChatClient(dio: dio);
    final request = AiChatRequest(
      sessionId: 'conversation-a',
      settings: const AiSettings(
        apiKey: 'zen-key',
        baseUrl: 'https://opencode.ai/zen/go/v1',
        model: 'deepseek-v4-flash',
        autoGenerate: true,
        provider: AiProviderKind.opencode,
      ),
      systemPrompt: 'sys',
      userPrompt: 'user',
    );
    await client.complete(request);
    await client.complete(request);

    expect(path, '/zen/go/v1/chat/completions');
    expect(body?['model'], 'deepseek-v4-flash');
    expect(body!.containsKey('thinking'), isFalse);
    expect(headersSeen, hasLength(2));
    expect(headersSeen[0]['x-opencode-session'], 'conversation-a');
    expect(headersSeen[1]['x-opencode-session'], 'conversation-a');
    expect(headersSeen[0]['User-Agent'], 'ledgerly-client/0.1.0');
  });

  test('opencode minimax uses messages and parses anthropic usage', () async {
    String? path;
    Map<String, dynamic>? body;
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
                'content': [
                  {'type': 'text', 'text': '{"headline":"ok"}'},
                ],
                'usage': {'input_tokens': 7, 'output_tokens': 5},
              },
            ),
          );
        },
      ),
    );

    final result = await OpenAiCompatibleChatClient(dio: dio).complete(
      const AiChatRequest(
        sessionId: 'conversation-minimax',
        settings: AiSettings(
          apiKey: 'zen-key',
          baseUrl: 'https://opencode.ai/zen/go/v1',
          model: 'minimax-m2.5',
          autoGenerate: true,
          provider: AiProviderKind.opencode,
        ),
        systemPrompt: 'sys',
        userPrompt: 'user',
      ),
    );

    expect(path, '/zen/go/v1/messages');
    expect(body?['system'], 'sys');
    expect(body?['messages'], [
      {'role': 'user', 'content': 'user'},
    ]);
    expect(result.text, '{"headline":"ok"}');
    expect(result.promptTokens, 7);
    expect(result.completionTokens, 5);
  });

  test('opencode gpt uses responses and parses output text', () async {
    String? path;
    Map<String, dynamic>? body;
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
                'output': [
                  {
                    'content': [
                      {'type': 'output_text', 'text': '{"headline":"ok"}'},
                    ],
                  },
                ],
                'usage': {'input_tokens': 11, 'output_tokens': 3},
              },
            ),
          );
        },
      ),
    );

    final result = await OpenAiCompatibleChatClient(dio: dio).complete(
      const AiChatRequest(
        sessionId: 'conversation-responses',
        settings: AiSettings(
          apiKey: 'zen-key',
          baseUrl: 'https://opencode.ai/zen/go/v1',
          model: 'gpt-5.6-luna',
          autoGenerate: true,
          provider: AiProviderKind.opencode,
        ),
        systemPrompt: 'sys',
        userPrompt: 'user',
      ),
    );

    expect(path, '/zen/go/v1/responses');
    expect(body?['instructions'], 'sys');
    expect(body?['input'], 'user');
    expect(result.text, '{"headline":"ok"}');
    expect(result.promptTokens, 11);
    expect(result.completionTokens, 3);
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
      () => OpenAiCompatibleChatClient(dio: dio).ping(
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

  test('cors failures explain the browser limitation', () {
    expect(
      describeAiError(
        DioException(
          requestOptions: RequestOptions(path: '/models'),
          type: DioExceptionType.connectionError,
          message:
              'XMLHttpRequest blocked by CORS: No Access-Control-Allow-Origin',
        ),
      ),
      contains('浏览器拦截了跨域请求'),
    );
  });
}
