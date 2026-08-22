import 'dart:convert';

import 'ai_models.dart';

AiInsightContent parseInsightContent(String raw) {
  final decoded = _decodeJsonObject(raw);
  if (decoded != null) {
    final headline = _asNonEmptyString(decoded['headline']);
    final highlights = _asStringList(decoded['highlights']);
    final advice = _asStringList(decoded['advice']);
    if (headline != null || highlights.isNotEmpty || advice.isNotEmpty) {
      return AiInsightContent(
        headline:
            headline ?? (highlights.isNotEmpty ? highlights.first : '消费总结'),
        highlights: highlights,
        advice: advice,
      );
    }
  }
  final text = raw.trim();
  return AiInsightContent(
    headline: text.isEmpty ? '消费总结' : text,
    highlights: const [],
    advice: const [],
  );
}

Map<String, dynamic>? decodeInsightBody(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

String encodeInsightBody(AiInsightContent content) {
  return jsonEncode({
    'headline': content.headline,
    'highlights': content.highlights,
    'advice': content.advice,
  });
}

Map<String, dynamic>? _decodeJsonObject(String raw) {
  final candidates = <String>[raw.trim()];
  final fenced = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(raw);
  if (fenced != null) {
    candidates.add(fenced.group(1)!.trim());
  }
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) {
    candidates.add(raw.substring(start, end + 1));
  }
  for (final candidate in candidates) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

String? _asNonEmptyString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
