import 'package:flutter/material.dart';

import '../../ai/ai_models.dart';
import '../../ai/insight_period.dart';
import '../design/ledgerly_theme.dart';
import 'ledgerly_layout.dart';

class AiInsightCard extends StatelessWidget {
  const AiInsightCard({
    super.key,
    required this.view,
    this.onConfigure,
    this.onGenerate,
    this.busy = false,
  });

  final AiInsightView view;
  final VoidCallback? onConfigure;
  final VoidCallback? onGenerate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return LedgerlySection(
      title: _title(),
      trailing: _trailing(context),
      child: busy
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : _body(context),
    );
  }

  String _title() {
    final kind = insightKindLabel(view.kind);
    final label = view.periodLabel;
    if (label == null || label.isEmpty) return 'AI $kind';
    return 'AI $kind · $label';
  }

  Widget? _trailing(BuildContext context) {
    if (view.status == AiInsightStatus.unconfigured) {
      return TextButton(
        key: const Key('ai-insight-configure'),
        onPressed: onConfigure,
        child: const Text('去配置'),
      );
    }
    if (onGenerate == null) return null;
    return TextButton(
      key: const Key('ai-insight-generate'),
      onPressed: busy ? null : onGenerate,
      child: Text(view.status == AiInsightStatus.ready ? '重新生成' : '生成'),
    );
  }

  Widget _body(BuildContext context) {
    switch (view.status) {
      case AiInsightStatus.unconfigured:
        return Text(
          '配置 DeepSeek API Key 后，可自动生成每日消费总结，并在新月补齐上月月报。默认模型不支持语音转文字。',
          style: Theme.of(context).textTheme.bodyMedium,
        );
      case AiInsightStatus.empty:
        return Text(
          view.generatedAt == null
              ? (view.headline ?? '尚未生成分析')
              : (view.headline ?? '暂无消费，未调用模型。'),
          style: Theme.of(context).textTheme.bodyMedium,
        );
      case AiInsightStatus.error:
        return Text(
          view.errorMessage ?? view.headline ?? '分析失败',
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
                  '账目已更新，可重新生成。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: LedgerlyColors.warning,
                  ),
                ),
              ),
            Text(
              view.headline ?? '消费总结',
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
                _usageCaption(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        );
    }
  }

  String _usageCaption() {
    final model = view.model ?? AiSettings.defaultModel;
    final prompt = view.promptTokens;
    final completion = view.completionTokens;
    if (prompt == null && completion == null) return model;
    return '$model · 入 ${prompt ?? '-'} / 出 ${completion ?? '-'} tokens';
  }
}
