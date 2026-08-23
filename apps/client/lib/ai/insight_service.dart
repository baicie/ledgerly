import '../data/ledger_repository.dart';
import '../domain/ids.dart';
import '../l10n/l10n.dart';
import 'ai_models.dart';
import 'chat_client.dart';
import 'insight_parser.dart';
import 'insight_period.dart';
import 'insight_prompt.dart';
import 'insight_repository.dart';
import 'insight_snapshot.dart';

class InsightService {
  InsightService({
    required LedgerRepository ledgerRepository,
    required InsightRepository insightRepository,
    required AiChatClient chatClient,
    String bookId = defaultBookId,
  })  : _ledger = ledgerRepository,
        _insights = insightRepository,
        _chat = chatClient,
        _bookId = bookId;

  final LedgerRepository _ledger;
  final InsightRepository _insights;
  final AiChatClient _chat;
  final String _bookId;
  final _inFlight = <String, Future<AiInsightView>>{};

  Future<AiInsightView> load(
    InsightPeriod period, {
    required AiSettings settings,
  }) async {
    if (!settings.isConfigured) {
      return AiInsightView.unconfigured(kind: period.kind);
    }
    final stored = await _insights.get(_bookId, period);
    final snapshot = await _snapshot(period);
    return _toView(period, stored, snapshot.hash);
  }

  Future<AiInsightView> ensure(
    InsightPeriod period, {
    required AiSettings settings,
    bool force = false,
  }) async {
    if (!settings.isConfigured) {
      return AiInsightView.unconfigured(kind: period.kind);
    }
    final key = insightRecordId(_bookId, period);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _ensure(period, settings: settings, force: force);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<AiInsightView> _ensure(
    InsightPeriod period, {
    required AiSettings settings,
    required bool force,
  }) async {
    if (!settings.isConfigured) {
      return AiInsightView.unconfigured(kind: period.kind);
    }

    final snapshot = await _snapshot(period);
    final stored = await _insights.get(_bookId, period);
    final stale = stored != null && stored.inputHash != snapshot.hash;
    if (!force &&
        stored != null &&
        stored.promptVersion == settings.resolvedPromptVersion &&
        stored.inputHash == snapshot.hash) {
      return _toView(period, stored, snapshot.hash);
    }

    if (!snapshot.hasActivity) {
      final empty = StoredInsight(
        id: insightRecordId(_bookId, period),
        bookId: _bookId,
        period: period,
        status: AiInsightStatus.empty,
        inputHash: snapshot.hash,
        model: settings.model,
        promptVersion: settings.resolvedPromptVersion,
        generatedAt: DateTime.now().toUtc(),
        headline: period.kind == InsightKind.daily
            ? L10n.current.insightEmptyDaily
            : L10n.current.insightEmptyMonthly,
        content: const AiInsightContent(
          headline: '',
          highlights: [],
          advice: [],
        ),
      );
      await _insights.upsert(empty);
      return _toView(period, empty, snapshot.hash);
    }

    try {
      final result = await _chat.complete(
        AiChatRequest(
          settings: settings,
          systemPrompt: resolveInsightSystemPrompt(settings),
          userPrompt: buildInsightUserPrompt(snapshot),
        ),
      );
      final parsed = parseInsightContent(result.text);
      final ready = StoredInsight(
        id: insightRecordId(_bookId, period),
        bookId: _bookId,
        period: period,
        status: AiInsightStatus.ready,
        inputHash: snapshot.hash,
        model: settings.model,
        promptVersion: settings.resolvedPromptVersion,
        generatedAt: DateTime.now().toUtc(),
        headline: parsed.headline,
        content: parsed,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
      );
      await _insights.upsert(ready);
      return _toView(period, ready, snapshot.hash);
    } catch (error) {
      final failed = StoredInsight(
        id: insightRecordId(_bookId, period),
        bookId: _bookId,
        period: period,
        status: AiInsightStatus.error,
        inputHash: snapshot.hash,
        model: settings.model,
        promptVersion: settings.resolvedPromptVersion,
        generatedAt: DateTime.now().toUtc(),
        errorMessage: error.toString(),
        headline: error.toString(),
      );
      await _insights.upsert(failed);
      return _toView(period, failed, snapshot.hash, stale: stale);
    }
  }

  Future<Map<String, AiInsightView>> loadDailyViews({
    required DateTime month,
    required List<TransactionSummary> transactions,
    required AiSettings settings,
    DateTime? now,
  }) async {
    final clock = (now ?? DateTime.now()).toLocal();
    final grouped = <String, List<TransactionSummary>>{};
    for (final transaction in transactions) {
      final period = InsightPeriod.daily(transaction.occurredAt);
      grouped.putIfAbsent(period.key, () => []).add(transaction);
    }
    final isCurrentMonth =
        month.year == clock.year && month.month == clock.month;
    if (isCurrentMonth) {
      grouped.putIfAbsent(InsightPeriod.daily(clock).key, () => []);
    }

    final prefix =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final stored = settings.isConfigured
        ? await _insights.listDaily(_bookId, prefix)
        : const <StoredInsight>[];
    final byKey = {for (final item in stored) item.period.key: item};

    final views = <String, AiInsightView>{};
    for (final key in grouped.keys) {
      final period = InsightPeriod.daily(DateTime.parse(key));
      if (!settings.isConfigured) {
        views[key] = AiInsightView(
          status: AiInsightStatus.unconfigured,
          kind: InsightKind.daily,
          periodKey: period.key,
          periodLabel: period.label,
        );
        continue;
      }
      final snapshot = buildInsightSnapshot(
        period: period,
        transactions: grouped[key] ?? const [],
      );
      views[key] = _toView(period, byKey[key], snapshot.hash);
    }
    return views;
  }

  Future<InsightSnapshot> _snapshot(InsightPeriod period) async {
    await _ledger.seedIfEmpty();
    final transactions = await _ledger.watchSummariesSync(
      _bookId,
      monthStart: period.start,
      monthEnd: period.end,
    );
    return buildInsightSnapshot(period: period, transactions: transactions);
  }

  AiInsightView _toView(
    InsightPeriod period,
    StoredInsight? stored,
    String currentHash, {
    bool stale = false,
  }) {
    if (stored == null) {
      return AiInsightView(
        status: AiInsightStatus.empty,
        kind: period.kind,
        periodKey: period.key,
        periodLabel: period.label,
        headline: L10n.current.insightNotGenerated,
      );
    }
    return AiInsightView(
      status: stored.status,
      kind: stored.period.kind,
      periodKey: stored.period.key,
      periodLabel: stored.period.label,
      headline: stored.headline ?? stored.content.headline,
      highlights: stored.content.highlights,
      advice: stored.content.advice,
      errorMessage: stored.errorMessage,
      model: stored.model,
      promptTokens: stored.promptTokens,
      completionTokens: stored.completionTokens,
      generatedAt: stored.generatedAt,
      stale: stale || stored.inputHash != currentHash,
    );
  }
}

class InsightScheduler {
  InsightScheduler(this._service);

  final InsightService _service;

  Future<void> ensureDueInsights({
    required AiSettings settings,
    DateTime? now,
    bool force = false,
  }) async {
    if (!settings.isConfigured || !settings.autoGenerate) return;
    final clock = now ?? DateTime.now();
    for (final period in InsightPeriod.duePeriods(clock)) {
      await _service.ensure(period, settings: settings, force: force);
    }
  }
}
