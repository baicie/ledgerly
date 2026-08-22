import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/ai/chat_client.dart';
import 'package:ledgerly_client/ai/insight_period.dart';
import 'package:ledgerly_client/ai/insight_repository.dart';
import 'package:ledgerly_client/ai/insight_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late LedgerAppService app;
  late InsightRepository insights;
  late FakeAiChatClient chat;
  late InsightService service;
  late InsightScheduler scheduler;

  const configured = AiSettings(
    apiKey: 'sk-test',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    autoGenerate: true,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = LedgerRepository(db, deviceIdLoader: () async => 'ai-device');
    app = LedgerAppService(ledger);
    insights = InsightRepository(db);
    chat = FakeAiChatClient();
    service = InsightService(
      ledgerRepository: ledger,
      insightRepository: insights,
      chatClient: chat,
    );
    scheduler = InsightScheduler(service);
    await ledger.seedIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  test('does not call the model without a key or for empty days', () async {
    final period = InsightPeriod.daily(DateTime(2026, 8, 22, 10));
    final unset = await service.ensure(
      period,
      settings: AiSettings.unset,
    );
    expect(unset.status, AiInsightStatus.unconfigured);
    expect(chat.requests, isEmpty);

    final empty = await service.ensure(period, settings: configured);
    expect(empty.status, AiInsightStatus.empty);
    expect(chat.requests, isEmpty);
  });

  test(
    'reuses a matching hash and scheduler covers yesterday plus last month',
    () async {
      await app.createExpense(
        expenseAccountId: accountKeyFood(defaultBookId),
        fundingAccountId: accountKeyCash(defaultBookId),
        amountMinor: BigInt.from(1800),
        description: '七月晚饭',
        occurredAt: DateTime(2026, 7, 15, 19),
      );
      await app.createExpense(
        expenseAccountId: accountKeyFood(defaultBookId),
        fundingAccountId: accountKeyCash(defaultBookId),
        amountMinor: BigInt.from(2200),
        description: '昨天午饭',
        occurredAt: DateTime(2026, 7, 31, 12),
      );
      await app.createExpense(
        expenseAccountId: accountKeyFood(defaultBookId),
        fundingAccountId: accountKeyCash(defaultBookId),
        amountMinor: BigInt.from(900),
        description: '今天咖啡',
        occurredAt: DateTime(2026, 8, 1, 9),
      );

      await scheduler.ensureDueInsights(
        settings: configured,
        now: DateTime(2026, 8, 1, 10),
      );
      expect(chat.requests, hasLength(3));

      await scheduler.ensureDueInsights(
        settings: configured,
        now: DateTime(2026, 8, 1, 11),
      );
      expect(chat.requests, hasLength(3));

      final monthly = await service.load(
        InsightPeriod.previousMonth(DateTime(2026, 8, 1, 10)),
        settings: configured,
      );
      expect(monthly.status, AiInsightStatus.ready);
      expect(monthly.headline, '餐饮占比较高');
      expect(monthly.promptTokens, 12);
    },
  );

  test('disabled auto generate skips due jobs', () async {
    await scheduler.ensureDueInsights(
      settings: configured.copyWith(autoGenerate: false),
      now: DateTime(2026, 8, 1, 10),
    );
    expect(chat.requests, isEmpty);
  });
}
