import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_models.dart';
import '../ai/ai_settings_store.dart';
import '../ai/chat_client.dart';
import '../ai/insight_period.dart';
import '../ai/insight_repository.dart';
import '../ai/insight_service.dart';
import 'providers.dart';

final aiSettingsStoreProvider = Provider<AiSettingsStore>((ref) {
  return createPlatformAiSettingsStore();
});

final aiSettingsControllerProvider =
    ChangeNotifierProvider<AiSettingsController>((ref) {
      final controller = AiSettingsController(
        store: ref.watch(aiSettingsStoreProvider),
      );
      unawaited(controller.load());
      return controller;
    });

final aiChatClientProvider = Provider<AiChatClient>((ref) {
  return DeepSeekChatClient();
});

final insightRepositoryProvider = Provider<InsightRepository>((ref) {
  return InsightRepository(ref.watch(databaseProvider));
});

final insightServiceProvider = Provider<InsightService>((ref) {
  return InsightService(
    ledgerRepository: ref.watch(ledgerRepositoryProvider),
    insightRepository: ref.watch(insightRepositoryProvider),
    chatClient: ref.watch(aiChatClientProvider),
  );
});

final insightSchedulerProvider = Provider<InsightScheduler>((ref) {
  return InsightScheduler(ref.watch(insightServiceProvider));
});

final aiInsightBootstrapProvider = FutureProvider<void>((ref) async {
  final settings = ref.watch(aiSettingsControllerProvider).settings;
  if (!settings.isConfigured) return;
  await ref
      .read(insightSchedulerProvider)
      .ensureDueInsights(settings: settings);
});

final todayAiInsightProvider = FutureProvider<AiInsightView>((ref) async {
  final settings = ref.watch(aiSettingsControllerProvider).settings;
  if (!settings.isConfigured) {
    return const AiInsightView.unconfigured(kind: InsightKind.daily);
  }
  await ref.watch(aiInsightBootstrapProvider.future);
  return ref
      .read(insightServiceProvider)
      .load(InsightPeriod.daily(DateTime.now()), settings: settings);
});

final previousMonthHighlightProvider = FutureProvider<AiInsightView?>((
  ref,
) async {
  final now = DateTime.now();
  if (!InsightPeriod.highlightPreviousMonth(now)) return null;
  final settings = ref.watch(aiSettingsControllerProvider).settings;
  if (!settings.isConfigured) return null;
  await ref.watch(aiInsightBootstrapProvider.future);
  return ref
      .read(insightServiceProvider)
      .load(InsightPeriod.previousMonth(now), settings: settings);
});

final selectedMonthAiInsightProvider = FutureProvider<AiInsightView>((
  ref,
) async {
  final settings = ref.watch(aiSettingsControllerProvider).settings;
  final period = InsightPeriod.monthOf(ref.watch(selectedMonthProvider));
  if (!settings.isConfigured) {
    return AiInsightView.unconfigured(kind: period.kind);
  }
  await ref.watch(aiInsightBootstrapProvider.future);
  return ref.read(insightServiceProvider).load(period, settings: settings);
});

Future<void> regenerateAiInsight(
  WidgetRef ref,
  InsightPeriod period, {
  bool force = true,
}) async {
  final settings = ref.read(aiSettingsControllerProvider).settings;
  await ref
      .read(insightServiceProvider)
      .ensure(period, settings: settings, force: force);
  ref.invalidate(aiInsightBootstrapProvider);
  ref.invalidate(todayAiInsightProvider);
  ref.invalidate(previousMonthHighlightProvider);
  ref.invalidate(selectedMonthAiInsightProvider);
}
