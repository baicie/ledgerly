import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/ai/insight_parser.dart';
import 'package:ledgerly_client/ai/insight_period.dart';
import 'package:ledgerly_client/ai/insight_prompt.dart';
import 'package:ledgerly_client/ai/insight_snapshot.dart';
import 'package:ledgerly_client/ai/ai_models.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';

void main() {
  group('InsightPeriod', () {
    test('builds local calendar day and previous month windows', () {
      final now = DateTime(2026, 8, 1, 9, 30);
      final today = InsightPeriod.daily(now);
      final yesterday = InsightPeriod.dailyOffset(now, -1);
      final lastMonth = InsightPeriod.previousMonth(now);

      expect(today.kind, InsightKind.daily);
      expect(today.key, '2026-08-01');
      expect(yesterday.key, '2026-07-31');
      expect(lastMonth.kind, InsightKind.monthly);
      expect(lastMonth.key, '2026-07');
      expect(InsightPeriod.duePeriods(now).map((period) => period.key), [
        '2026-08-01',
        '2026-07-31',
        '2026-07',
      ]);
      expect(InsightPeriod.highlightPreviousMonth(now), isTrue);
      expect(
        InsightPeriod.highlightPreviousMonth(DateTime(2026, 8, 4)),
        isFalse,
      );
    });

    test('previous month crosses the year boundary', () {
      expect(InsightPeriod.previousMonth(DateTime(2026, 1, 1)).key, '2025-12');
    });
  });

  group('snapshot and parser', () {
    test('builds yuan amounts, chinese categories, and no account ids', () {
      final period = InsightPeriod.daily(DateTime(2026, 8, 21, 18));
      final snapshot = buildInsightSnapshot(
        period: period,
        transactions: [
          TransactionSummary(
            id: 'tx-1',
            occurredAt: DateTime(2026, 8, 21, 12, 30),
            description: '午餐',
            entryCount: 2,
            kind: TransactionSummaryKind.expense,
            amountMinor: BigInt.from(3200),
            categoryName: 'Food',
            accountName: 'Cash',
            accountId: 'book_default:acc_cash',
            categoryAccountId: 'book_default:acc_food',
          ),
        ],
      );

      expect(snapshot.hasActivity, isTrue);
      expect(snapshot.payload['totals'], containsPair('expense', '32.00'));
      final encoded = snapshot.userPrompt;
      expect(encoded, contains('餐饮'));
      expect(encoded, contains('午餐'));
      expect(encoded, isNot(contains('book_default:acc_cash')));
      expect(encoded, isNot(contains('accountId')));
      expect(buildInsightUserPrompt(snapshot), contains('每日消费总结'));
    });

    test('resolves built-in and custom system prompts with json contract', () {
      const balanced = AiSettings(
        apiKey: 'sk',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        autoGenerate: true,
      );
      expect(resolveInsightSystemPrompt(balanced), contains('总结消费结构'));
      expect(resolveInsightSystemPrompt(balanced), contains('必须只输出 JSON'));

      final frugal = balanced.copyWith(promptPreset: AiPromptPreset.frugal);
      expect(resolveInsightSystemPrompt(frugal), contains('偏节约'));
      expect(frugal.resolvedPromptVersion, 'spend-insight.v2:frugal');

      final custom = balanced.copyWith(
        promptPreset: AiPromptPreset.custom,
        customSystemPrompt: '只点评咖啡支出。',
      );
      final prompt = resolveInsightSystemPrompt(custom);
      expect(prompt, contains('只点评咖啡支出。'));
      expect(prompt, contains('必须只输出 JSON'));
      expect(
          custom.resolvedPromptVersion, startsWith('spend-insight.v2:custom:'));
    });

    test('parses json even when wrapped in markdown', () {
      final parsed = parseInsightContent(
        '```json\n{"headline":"餐饮偏高","highlights":["午餐 32 元"],"advice":["可带饭"]}\n```',
      );
      expect(parsed.headline, '餐饮偏高');
      expect(parsed.highlights, ['午餐 32 元']);
      expect(parsed.advice, ['可带饭']);
    });

    test('falls back to raw text when json is missing', () {
      final parsed = parseInsightContent('今天花得不多');
      expect(parsed.headline, '今天花得不多');
      expect(parsed.highlights, isEmpty);
    });
  });
}
