import 'insight_snapshot.dart';

const insightSystemPrompt = '你是 Ledgerly 的中文理财助手。根据用户提供的 JSON 账本切片，总结消费结构。'
    '只依据给定数据，不要编造未出现的商户或金额。'
    '关注支出结构、异常大额、是否集中在少数分类，并给出可执行的下一句建议。'
    '必须只输出 JSON 对象，键为 headline（string）、highlights（string 数组，3 到 5 条）、'
    'advice（string 数组，1 到 2 条）。不要输出 markdown。';

String buildInsightUserPrompt(InsightSnapshot snapshot) {
  final kind = snapshot.period.kind.name == 'daily' ? '每日' : '月度';
  return '请生成$kind消费总结。金额单位是元，币种见 JSON。\n${snapshot.userPrompt}';
}
