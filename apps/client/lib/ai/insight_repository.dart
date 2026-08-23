import 'package:drift/drift.dart';

import '../data/database.dart';
import '../l10n/l10n.dart';
import 'ai_models.dart';
import 'insight_parser.dart';
import 'insight_period.dart';

class StoredInsight {
  const StoredInsight({
    required this.id,
    required this.bookId,
    required this.period,
    required this.status,
    required this.inputHash,
    required this.model,
    required this.promptVersion,
    required this.generatedAt,
    this.headline,
    this.content = const AiInsightContent(
      headline: '',
      highlights: [],
      advice: [],
    ),
    this.errorMessage,
    this.promptTokens,
    this.completionTokens,
  });

  final String id;
  final String bookId;
  final InsightPeriod period;
  final AiInsightStatus status;
  final String inputHash;
  final String model;
  final String promptVersion;
  final DateTime generatedAt;
  final String? headline;
  final AiInsightContent content;
  final String? errorMessage;
  final int? promptTokens;
  final int? completionTokens;
}

class InsightRepository {
  InsightRepository(this._db);

  final AppDatabase _db;

  Future<StoredInsight?> get(String bookId, InsightPeriod period) async {
    final id = insightRecordId(bookId, period);
    final row = await _db.customSelect(
      'SELECT * FROM ai_insights WHERE id = ?',
      variables: [Variable<String>(id)],
      readsFrom: {},
    ).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<List<StoredInsight>> listDaily(
      String bookId, String monthPrefix) async {
    final rows = await _db.customSelect(
      '''
SELECT * FROM ai_insights
WHERE book_id = ? AND kind = ? AND period_key LIKE ?
ORDER BY period_key DESC
''',
      variables: [
        Variable<String>(bookId),
        Variable<String>(InsightKind.daily.name),
        Variable<String>('$monthPrefix-%'),
      ],
      readsFrom: {},
    ).get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<void> upsert(StoredInsight insight) async {
    final headline = insight.status == AiInsightStatus.error
        ? insight.errorMessage
        : (insight.headline ?? insight.content.headline);
    final body = insight.status == AiInsightStatus.error
        ? encodeInsightBody(
            AiInsightContent(
              headline: insight.errorMessage ?? L10n.current.insightFailed,
              highlights: const [],
              advice: const [],
            ),
          )
        : encodeInsightBody(insight.content);
    await _db.customInsert(
      '''
INSERT OR REPLACE INTO ai_insights (
  id, book_id, kind, period_key, period_start, period_end, model,
  prompt_version, input_hash, status, headline, body_json,
  prompt_tokens, completion_tokens, generated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      variables: [
        Variable<String>(insight.id),
        Variable<String>(insight.bookId),
        Variable<String>(insight.period.kind.name),
        Variable<String>(insight.period.key),
        Variable<int>(_epochMillis(insight.period.start)),
        Variable<int>(_epochMillis(insight.period.end)),
        Variable<String>(insight.model),
        Variable<String>(insight.promptVersion),
        Variable<String>(insight.inputHash),
        Variable<String>(insight.status.name),
        Variable<String>(headline ?? ''),
        Variable<String>(body),
        insight.promptTokens == null
            ? const Variable<int>(null)
            : Variable<int>(insight.promptTokens!),
        insight.completionTokens == null
            ? const Variable<int>(null)
            : Variable<int>(insight.completionTokens!),
        Variable<int>(_epochMillis(insight.generatedAt)),
      ],
      updates: {},
    );
  }

  StoredInsight _fromRow(QueryRow row) {
    final kind = row.read<String>('kind') == InsightKind.monthly.name
        ? InsightKind.monthly
        : InsightKind.daily;
    final body = decodeInsightBody(row.read<String>('body_json')) ?? const {};
    final statusName = row.read<String>('status');
    final status = switch (statusName) {
      'empty' => AiInsightStatus.empty,
      'error' => AiInsightStatus.error,
      _ => AiInsightStatus.ready,
    };
    final headline = row.readNullable<String>('headline');
    return StoredInsight(
      id: row.read<String>('id'),
      bookId: row.read<String>('book_id'),
      period: InsightPeriod(
        kind: kind,
        key: row.read<String>('period_key'),
        start: _fromEpochMillis(row.read<int>('period_start')),
        end: _fromEpochMillis(row.read<int>('period_end')),
      ),
      status: status,
      inputHash: row.read<String>('input_hash'),
      model: row.read<String>('model'),
      promptVersion: row.read<String>('prompt_version'),
      generatedAt: _fromEpochMillis(row.read<int>('generated_at')),
      headline: headline,
      content: AiInsightContent(
        headline: headline ?? body['headline']?.toString() ?? '',
        highlights: [
          if (body['highlights'] is List)
            for (final item in body['highlights'] as List)
              if (item != null && item.toString().trim().isNotEmpty)
                item.toString().trim(),
        ],
        advice: [
          if (body['advice'] is List)
            for (final item in body['advice'] as List)
              if (item != null && item.toString().trim().isNotEmpty)
                item.toString().trim(),
        ],
      ),
      errorMessage: status == AiInsightStatus.error
          ? headline ?? body['headline']?.toString()
          : null,
      promptTokens: row.readNullable<int>('prompt_tokens'),
      completionTokens: row.readNullable<int>('completion_tokens'),
    );
  }

  static int _epochMillis(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch;

  static DateTime _fromEpochMillis(int value) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
}
