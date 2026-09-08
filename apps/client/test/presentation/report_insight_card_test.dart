import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/ai/ai_settings_store.dart';
import 'package:ledgerly_client/ai/insight_period.dart';
import 'package:ledgerly_client/presentation/ai_providers.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/presentation/widgets/report_insight_card.dart';

void main() {
  group('ReportsInsightCard', () {
    testWidgets('renders unconfigured CTA when AI is not configured',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(
                kind: InsightKind.monthly,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReportsInsightCard(
                period: InsightPeriod.monthOf(DateTime(2026, 8)),
                onConfigure: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 总结'), findsOneWidget);
      expect(find.textContaining('Connect an AI provider'), findsNothing);
      expect(find.textContaining('接入 AI 服务'), findsOneWidget);
      expect(find.text('去配置'), findsOneWidget);
    });

    testWidgets('renders ready highlights and advice', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView(
                status: AiInsightStatus.ready,
                kind: InsightKind.monthly,
                periodKey: '2026-08',
                periodLabel: '2026年8月',
                headline: '本月支出偏高',
                highlights: ['餐饮支出 +20%', '新增订阅类支出'],
                advice: ['取消一项未使用的订阅', '本周餐饮控制在 200 元内'],
                model: 'deepseek-v4-flash',
                promptTokens: 1500,
                completionTokens: 240,
                generatedAt: null,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReportsInsightCard(
                period: InsightPeriod.monthOf(DateTime(2026, 8)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('本月支出偏高'), findsOneWidget);
      expect(find.text('重点'), findsOneWidget);
      expect(find.text('餐饮支出 +20%'), findsOneWidget);
      expect(find.text('新增订阅类支出'), findsOneWidget);
      expect(find.text('建议'), findsOneWidget);
      expect(find.text('取消一项未使用的订阅'), findsOneWidget);
      expect(find.textContaining('deepseek-v4-flash'), findsOneWidget);
    });

    testWidgets('renders error state when insight fails', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView(
                status: AiInsightStatus.error,
                kind: InsightKind.monthly,
                periodKey: '2026-08',
                periodLabel: '2026年8月',
                errorMessage: 'rate limit exceeded',
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReportsInsightCard(
                period: InsightPeriod.monthOf(DateTime(2026, 8)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('rate limit exceeded'), findsOneWidget);
    });

    testWidgets('hides configure CTA when onConfigure is null', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiEndpointProvider.overrideWithValue(null),
            aiSettingsStoreProvider.overrideWithValue(MemoryAiSettingsStore()),
            selectedMonthAiInsightProvider.overrideWith(
              (ref) async => const AiInsightView.unconfigured(
                kind: InsightKind.monthly,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReportsInsightCard(
                period: InsightPeriod.monthOf(DateTime(2026, 8)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('去配置'), findsNothing);
    });
  });
}
