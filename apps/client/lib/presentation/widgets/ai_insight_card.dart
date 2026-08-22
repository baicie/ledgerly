import 'package:flutter/material.dart';

import '../../ai/ai_models.dart';
import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import 'ledgerly_layout.dart';

class AiInsightCard extends StatefulWidget {
  const AiInsightCard({
    super.key,
    required this.view,
    this.onConfigure,
    this.onGenerate,
    this.busy = false,
    this.embedded = false,
    this.initiallyExpanded = false,
  });

  final AiInsightView view;
  final VoidCallback? onConfigure;
  final VoidCallback? onGenerate;
  final bool busy;
  final bool embedded;
  final bool initiallyExpanded;

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  late bool _expanded = widget.initiallyExpanded;

  AiInsightView get view => widget.view;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, l10n),
        if (_expanded)
          Padding(
            padding: widget.embedded
                ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
                : const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: widget.busy
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _body(context, l10n),
          ),
      ],
    );
    if (widget.embedded) return content;
    return LedgerlySection(padding: EdgeInsets.zero, child: content);
  }

  Widget _header(BuildContext context, AppLocalizations l10n) {
    final preview = _expanded ? null : _collapsedPreview(l10n);
    final trailing = _trailing(l10n);
    return InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(l10n),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
            IconButton(
              key: const Key('ai-insight-toggle'),
              tooltip: _expanded ? l10n.insightCollapse : l10n.insightExpand,
              onPressed: _toggle,
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);

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

  String? _collapsedPreview(AppLocalizations l10n) {
    switch (view.status) {
      case AiInsightStatus.unconfigured:
        return null;
      case AiInsightStatus.empty:
        if (view.generatedAt == null) return l10n.insightNotGenerated;
        return view.kind == InsightKind.daily
            ? l10n.insightEmptyDaily
            : l10n.insightEmptyMonthly;
      case AiInsightStatus.error:
        return view.errorMessage ?? view.headline ?? l10n.insightFailed;
      case AiInsightStatus.ready:
        return view.headline ?? l10n.insightFallbackHeadline;
    }
  }

  Widget? _trailing(AppLocalizations l10n) {
    if (view.status == AiInsightStatus.unconfigured) {
      return TextButton(
        key: const Key('ai-insight-configure'),
        onPressed: widget.onConfigure,
        child: Text(l10n.goConfigure),
      );
    }
    if (widget.onGenerate == null) return null;
    return TextButton(
      key: const Key('ai-insight-generate'),
      onPressed: widget.busy ? null : widget.onGenerate,
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
