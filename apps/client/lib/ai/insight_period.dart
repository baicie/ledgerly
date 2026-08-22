import 'ai_models.dart';

class InsightPeriod {
  const InsightPeriod({
    required this.kind,
    required this.key,
    required this.start,
    required this.end,
  });

  final InsightKind kind;
  final String key;
  final DateTime start;
  final DateTime end;

  String get label {
    switch (kind) {
      case InsightKind.daily:
        final local = start.toLocal();
        return '${local.year}年${local.month}月${local.day}日';
      case InsightKind.monthly:
        final local = start.toLocal();
        return '${local.year}年${local.month}月';
    }
  }

  static InsightPeriod daily(DateTime now) {
    final local = now.toLocal();
    return _dailyOn(local.year, local.month, local.day);
  }

  static InsightPeriod dailyOffset(DateTime now, int dayOffset) {
    final local = now.toLocal();
    final day = DateTime(local.year, local.month, local.day + dayOffset);
    return _dailyOn(day.year, day.month, day.day);
  }

  static InsightPeriod monthOf(DateTime month) {
    final local = month.toLocal();
    return _monthOn(local.year, local.month);
  }

  static InsightPeriod previousMonth(DateTime now) {
    final local = now.toLocal();
    final month = DateTime(local.year, local.month - 1);
    return _monthOn(month.year, month.month);
  }

  static List<InsightPeriod> duePeriods(DateTime now) {
    return [daily(now), dailyOffset(now, -1), previousMonth(now)];
  }

  static bool highlightPreviousMonth(DateTime now) {
    return now.toLocal().day <= 3;
  }

  @override
  bool operator ==(Object other) {
    return other is InsightPeriod && other.kind == kind && other.key == key;
  }

  @override
  int get hashCode => Object.hash(kind, key);

  static InsightPeriod _dailyOn(int year, int month, int day) {
    final startLocal = DateTime(year, month, day);
    final endLocal = DateTime(year, month, day + 1);
    return InsightPeriod(
      kind: InsightKind.daily,
      key:
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      start: startLocal.toUtc(),
      end: endLocal.toUtc(),
    );
  }

  static InsightPeriod _monthOn(int year, int month) {
    final startLocal = DateTime(year, month);
    final endLocal = DateTime(year, month + 1);
    return InsightPeriod(
      kind: InsightKind.monthly,
      key:
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}',
      start: startLocal.toUtc(),
      end: endLocal.toUtc(),
    );
  }
}

String insightRecordId(String bookId, InsightPeriod period) {
  return '$bookId:${period.kind.name}:${period.key}';
}

String localizedInsightName(String? name) {
  if (name == null || name.isEmpty) return '未分类';
  switch (name) {
    case 'Cash':
      return '现金';
    case 'Bank':
      return '银行卡';
    case 'Transfer':
      return '账户转账';
    case 'Other':
      return '其他';
    default:
      return name;
  }
}
