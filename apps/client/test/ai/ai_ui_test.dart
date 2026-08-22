import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/ai/chat_client.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/pages/ai_settings_page.dart';
import 'package:ledgerly_client/presentation/widgets/ai_insight_card.dart';

void main() {
  testWidgets('settings page saves key and tests the connection', (
    tester,
  ) async {
    final store = MemoryAiSettingsStore();
    final chat = FakeAiChatClient();
    final controller = AiSettingsController(store: store);
    await controller.load();

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSettingsStoreProvider.overrideWithValue(store),
          aiSettingsControllerProvider.overrideWith((ref) => controller),
          aiChatClientProvider.overrideWithValue(chat),
        ],
        child: const MaterialApp(home: AiSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('不能语音转文字'), findsOneWidget);
    expect(find.textContaining('第一期不做累计用量'), findsOneWidget);
    expect(find.text('DeepSeek'), findsWidgets);

    await tester.tap(find.byKey(const Key('ai-settings-provider-deepseek')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenCode').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ai-settings-base-url')))
          .controller
          ?.text,
      'https://opencode.ai/zen/go/v1',
    );

    await tester.enterText(
      find.byKey(const Key('ai-settings-api-key')),
      'sk-live',
    );
    await tester.tap(find.byKey(const Key('ai-settings-test')));
    await tester.pumpAndSettle();
    expect(chat.pingCount, 1);
    expect(find.text('连接成功。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-settings-save')));
    await tester.pumpAndSettle();
    expect(store.value.apiKey, 'sk-live');
    expect(store.value.provider, AiProviderKind.opencode);
    expect(store.value.baseUrl, 'https://opencode.ai/zen/go/v1');
    expect(store.value.model, 'deepseek-v4-flash');
  });

  testWidgets('insight card explains unconfigured state', (tester) async {
    var configured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiInsightCard(
            view: const AiInsightView.unconfigured(kind: InsightKind.daily),
            onConfigure: () => configured = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('不支持语音转文字'), findsNothing);
    await tester.tap(find.byKey(const Key('ai-insight-configure')));
    expect(configured, isTrue);

    await tester.tap(find.byKey(const Key('ai-insight-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不支持语音转文字'), findsOneWidget);
  });

  testWidgets('monthly unconfigured card explains reports placement',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiInsightCard(
            view: AiInsightView.unconfigured(kind: InsightKind.monthly),
          ),
        ),
      ),
    );

    expect(find.textContaining('所选月份的消费月报'), findsNothing);
    await tester.tap(find.byKey(const Key('ai-insight-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('所选月份的消费月报'), findsOneWidget);
    expect(find.textContaining('当天流水'), findsNothing);
  });

  testWidgets('ready insight card stays collapsed until expanded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiInsightCard(
            view: AiInsightView(
              status: AiInsightStatus.ready,
              kind: InsightKind.monthly,
              periodLabel: '2026年7月',
              headline: '上月餐饮偏高',
              highlights: ['外卖 12 次'],
              advice: ['可改成自己做饭'],
              model: 'deepseek-v4-flash',
              promptTokens: 120,
              completionTokens: 40,
            ),
          ),
        ),
      ),
    );

    expect(find.text('上月餐饮偏高'), findsOneWidget);
    expect(find.text('· 外卖 12 次'), findsNothing);

    await tester.tap(find.byKey(const Key('ai-insight-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('· 外卖 12 次'), findsOneWidget);
    expect(
      find.text('deepseek-v4-flash · 入 120 / 出 40 tokens'),
      findsOneWidget,
    );
  });
}
