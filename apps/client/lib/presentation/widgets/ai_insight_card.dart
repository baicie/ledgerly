import 'package:flutter/material.dart';

import '../../ai/ai_models.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import 'ledgerly_layout.dart';

class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.view,
    this.onConfigure,
    this.onGenerate,
    this.busy = false,
    this.embedded = false,
  });

  final AiInsightView view;
  final VoidCallback? onConfigure;
  final VoidCallback? onGenerate;
  final bool busy;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final body = busy
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        : _body(context, l10n);
    if (embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title(l10n),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_trailing(l10n) != null) _trailing(l10n)!,
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      );
    }
    return LedgerlySection(
      title: _title(l10n),
      trailing: _trailing(l10n),
      child: body,
    );
  }

  String _title(AppLocalizations l10n) {
    final kind = insightKindLabel(l10n, view.kind.name);
    final label = insightPeriodLabel(
      l10n: l10n,
      kindName: view.kind.name,
      periodKey: view.periodKey,
      fallback: view.periodLabel,
    );
    if (label.isEmpty) return l10n.aiInsightTitleKindOnly(kind);
    return l10n.aiInsightTitleWithPeriod(kind, label);
  }

  Widget? _trailing(AppLocalizations l10n) {
    if (view.status == AiInsightStatus.unconfigured) {
      return TextButton(
        key: const Key('ai-insight-configure'),
        onPressed: onConfigure,
        child: Text(l10n.goConfigure),
      );
    }
    if (onGenerate == null) return null;
    return TextButton(
      key: const Key('ai-insight-generate'),
      onPressed: busy ? null : onGenerate,
      child: Text(
        view.status == AiInsightStatus.ready ? l10n.regenerate : l10n.generate,
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    switch (view.status) {
      case AiInsightStatus.unconfigured:
        return Text(
          view.kind == InsightKind.monthly
              ? l10n.insightUnconfiguredMonthly
              : l10n.insightUnconfiguredDaily,
          style: Theme.of(context).textTheme.bodyMedium,
        );
      case AiInsightStatus.empty:
        return Text(
          view.generatedAt == null
              ? l10n.insightNotGenerated
              : (view.kind == InsightKind.daily
                  ? l10n.insightEmptyDaily
                  : l10n.insightEmptyMonthly),
          style: Theme.of(context).textTheme.bodyMedium,
        );
      case AiInsightStatus.error:
        return Text(
          view.errorMessage ?? view.headline ?? l10n.insightFailed,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      case AiInsightStatus.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (view.stale)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.insightStale,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LedgerlyColors.warning,
                      ),
                ),
              ),
            Text(
              view.headline ?? l10n.insightFallbackHeadline,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (view.highlights.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in view.highlights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· $item',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
            ],
            if (view.advice.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in view.advice)
                Text(item, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (view.model != null) ...[
              const SizedBox(height: 10),
              Text(
                _usageCaption(l10n),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        );
    }
  }

  String _usageCaption(AppLocalizations l10n) {
    final model = view.model ?? AiSettings.defaultModel;
    final prompt = view.promptTokens;
    final completion = view.completionTokens;
    if (prompt == null && completion == null) return model;
    return l10n.tokenUsage(model, '${prompt ?? '-'}', '${completion ?? '-'}');
  }
}
