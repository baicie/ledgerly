import 'ai_models.dart';
import 'insight_snapshot.dart';

const insightJsonContract =
    '只依据给定数据，不要编造未出现的商户或金额。必须只输出 JSON 对象，键为 headline（string）、'
    'highlights（string 数组，3 到 5 条）、advice（string 数组，1 到 2 条）。不要输出 markdown。';

const insightPromptBalanced = '你是 Ledgerly 的中文理财助手。根据用户提供的 JSON 账本切片，总结消费结构。'
    '关注支出结构、异常大额、是否集中在少数分类，并给出可执行的下一句建议。';

const insightPromptFrugal = '你是偏节约的中文理财助手。根据账本切片找出可砍掉或可延后的支出，语气直接但不指责。'
    '优先指出外卖、订阅、冲动消费和重复开销。建议必须具体到下一笔可改的行为。';

const insightPromptReview = '你是复盘向的中文理财助手。按分类对比金额与笔数，标出占比最高和最异常的一笔。'
    '结论先事实后判断。建议侧重本周可执行的调整，而不是长期鸡汤。';

const insightPromptConcise =
    '你是极简中文理财助手。headline 不超过 18 字。highlights 只保留 3 条最重要的事实。'
    'advice 只给 1 条。不要重复堆砌切片里已经有的数字。';

String insightStylePrompt(AiPromptPreset preset, String customSystemPrompt) {
  return switch (preset) {
    AiPromptPreset.balanced => insightPromptBalanced,
    AiPromptPreset.frugal => insightPromptFrugal,
    AiPromptPreset.review => insightPromptReview,
    AiPromptPreset.concise => insightPromptConcise,
    AiPromptPreset.custom => customSystemPrompt.trim().isEmpty
        ? insightPromptBalanced
        : customSystemPrompt.trim(),
  };
}

String resolveInsightSystemPrompt(AiSettings settings) {
  final style = insightStylePrompt(
    settings.promptPreset,
    settings.customSystemPrompt,
  );
  if (style.contains('必须只输出 JSON')) return style;
  return '$style$insightJsonContract';
}

String buildInsightUserPrompt(InsightSnapshot snapshot) {
  final kind = snapshot.period.kind.name == 'daily' ? '每日' : '月度';
  return '请生成$kind消费总结。金额单位是元，币种见 JSON。\n${snapshot.userPrompt}';
}
