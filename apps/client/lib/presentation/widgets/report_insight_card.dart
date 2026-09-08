import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_models.dart';
import '../../ai/insight_period.dart';
import '../../l10n/l10n.dart';
import '../ai_providers.dart';

/// A standalone card for the Reports page that displays an AI monthly summary.
/// Drives generation/regeneration for an arbitrary [period]. Handles all states
/// (loading / unconfigured / empty / ready / error / stale).
class ReportsInsightCard extends ConsumerStatefulWidget {
  const ReportsInsightCard({
    super.key,
    required this.period,
    this.title,
    this.onConfigure,
  });

  /// Period used to fetch/generate the insight.
  final InsightPeriod period;

  /// Card heading; falls back to [L10n.current.aiInsightCardTitle].
  final String? title;

  /// Navigate to AI settings. Hidden when null.
  final VoidCallback? onConfigure;

  @override
  ConsumerState<ReportsInsightCard> createState() => _ReportsInsightCardState();
}

class _ReportsInsightCardState extends ConsumerState<ReportsInsightCard> {
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final viewAsync = ref.watch(selectedMonthAiInsightProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title ?? L10n.current.aiInsightCardTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: L10n.current.aiInsightRegenerate,
                  onPressed: _generating ? null : _regenerate,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            viewAsync.when(
              loading: () => const _LoadingBody(),
              error: (err, _) => _ErrorBody(message: err.toString()),
              data: (view) =>
                  _InsightBody(view: view, onConfigure: widget.onConfigure),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerate() async {
    setState(() => _generating = true);
    try {
      await regenerateAiInsight(ref, widget.period);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({required this.view, this.onConfigure});
  final AiInsightView view;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    switch (view.status) {
      case AiInsightStatus.unconfigured:
        return _UnconfiguredBody(onConfigure: onConfigure);
      case AiInsightStatus.empty:
        return _EmptyBody(headline: view.headline);
      case AiInsightStatus.error:
        return _ErrorBody(
          message: view.errorMessage ?? view.headline ?? 'Insight failed',
        );
      case AiInsightStatus.ready:
        return _ReadyBody(view: view);
    }
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.view});
  final AiInsightView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (view.headline != null && view.headline!.isNotEmpty) ...[
          Text(
            view.headline!,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
        ],
        if (view.highlights.isNotEmpty) ...[
          _SectionLabel(text: L10n.current.aiInsightHighlights),
          for (final item in view.highlights) _Bullet(text: item),
          const SizedBox(height: 12),
        ],
        if (view.advice.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      L10n.current.aiInsightAdvice,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final item in view.advice)
                  _Bullet(text: item, icon: Icons.tips_and_updates_outlined),
              ],
            ),
          ),
        ],
        if (view.stale) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.refresh, size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Text(
                L10n.current.aiInsightStale,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _InsightFooter(view: view),
      ],
    );
  }
}

class _UnconfiguredBody extends StatelessWidget {
  const _UnconfiguredBody({this.onConfigure});
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.current.aiInsightUnconfigured,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.current.aiInsightUnconfiguredDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onConfigure != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: onConfigure,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(L10n.current.aiInsightConfigure),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({this.headline});
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                headline ?? L10n.current.aiInsightEmpty,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                L10n.current.aiInsightEmptyDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline,
            color: theme.colorScheme.error, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBar(width: 180, height: 18, color: base),
          const SizedBox(height: 12),
          _SkeletonBar(width: double.infinity, height: 12, color: base),
          const SizedBox(height: 6),
          _SkeletonBar(width: double.infinity, height: 12, color: base),
          const SizedBox(height: 6),
          _SkeletonBar(width: 240, height: 12, color: base),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height, required this.color});
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.icon = Icons.circle});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Icon(icon, size: 10, color: theme.colorScheme.primary),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _InsightFooter extends StatelessWidget {
  const _InsightFooter({required this.view});
  final AiInsightView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    if (view.model != null && view.model!.isNotEmpty) {
      parts.add(view.model!);
    }
    if (view.generatedAt != null) {
      final local = view.generatedAt!.toLocal();
      final stamp =
          '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      parts.add(stamp);
    }
    if (view.promptTokens != null || view.completionTokens != null) {
      final tokens =
          (view.promptTokens ?? 0) + (view.completionTokens ?? 0);
      parts.add('$tokens tok');
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style:
          theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
    );
  }
}
