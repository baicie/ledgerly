import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/reports_range.dart';

void main() {
  group('ReportsRange', () {
    test('monthCount for each kind', () {
      expect(ReportsRange.month().monthCount, 1);
      expect(ReportsRange.last3Months().monthCount, 3);
      expect(ReportsRange.last6Months().monthCount, 6);
      expect(ReportsRange.year().monthCount, 12);
    });

    test('custom monthCount', () {
      final range = ReportsRange.custom(
        DateTime(2026, 1),
        DateTime(2026, 3),
      );
      expect(range.monthCount, 3);
    });

    test('isMultiMonth', () {
      expect(ReportsRange.month().isMultiMonth, isFalse);
      expect(ReportsRange.last3Months().isMultiMonth, isTrue);
      expect(ReportsRange.last6Months().isMultiMonth, isTrue);
      expect(ReportsRange.year().isMultiMonth, isTrue);
    });

    test('isMonthAnchored', () {
      expect(ReportsRange.month().isMonthAnchored, isTrue);
      expect(ReportsRange.last3Months().isMonthAnchored, isTrue);
      expect(ReportsRange.last6Months().isMonthAnchored, isTrue);
      expect(ReportsRange.year().isMonthAnchored, isFalse);
      expect(
          ReportsRange.custom(DateTime(2026, 1), DateTime(2026, 3))
              .isMonthAnchored,
          isFalse);
    });

    test('resolve() for month', () {
      final anchor = DateTime(2026, 3);
      final range = ReportsRange.month(anchor);
      final r = range.resolve();
      expect(r.start, DateTime(2026, 3, 1));
      expect(r.end, DateTime(2026, 4, 1));
    });

    test('resolve() for last3Months', () {
      final anchor = DateTime(2026, 3);
      final range = ReportsRange.last3Months(anchor);
      final r = range.resolve();
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2026, 4, 1));
    });

    test('resolve() for year', () {
      final anchor = DateTime(2026, 6);
      final range = ReportsRange.year(anchor);
      final r = range.resolve();
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2027, 1, 1));
    });

    test('withAnchor shifts anchor for anchored ranges', () {
      final range = ReportsRange.month(DateTime(2026, 3));
      final shifted = range.withAnchor(DateTime(2026, 5));
      expect(shifted.anchor, DateTime(2026, 5));
    });

    test('withAnchor returns same range for non-anchored', () {
      final range = ReportsRange.year(DateTime(2026, 3));
      final shifted = range.withAnchor(DateTime(2026, 5));
      // year is not anchored, so withAnchor returns this unchanged
      expect(shifted.kind, ReportsRangeKind.year);
    });

    test('equality and hashCode', () {
      final a = ReportsRange.month(DateTime(2026, 3));
      final b = ReportsRange.month(DateTime(2026, 3));
      final c = ReportsRange.month(DateTime(2026, 4));
      expect(a == b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
      expect(a == c, isFalse);
    });

    test('toJson / fromJson round-trip', () {
      final original = ReportsRange.custom(DateTime(2026, 1, 15), DateTime(2026, 6, 20));
      final json = original.toJson();
      final restored = ReportsRange.fromJson(json);
      expect(restored.kind, original.kind);
      expect(restored.customStart?.year, original.customStart?.year);
      expect(restored.customEnd?.year, original.customEnd?.year);
    });

    test('fromJson defaults to month for unknown kind', () {
      final json = {'kind': 'unknown', 'anchor': '2026-03-01T00:00:00.000'};
      final restored = ReportsRange.fromJson(json);
      expect(restored.kind, ReportsRangeKind.month);
    });

    test('lastNDays factory rejects unsupported values', () {
      expect(() => ReportsRange.lastNDays(14), throwsArgumentError);
      expect(() => ReportsRange.lastNDays(0), throwsArgumentError);
    });

    test('last7Days resolves to a 7-day window ending today', () {
      final range = ReportsRange.lastNDays(7);
      final r = range.resolve();
      final today = DateTime.now();
      final truncatedToday = DateTime(today.year, today.month, today.day);
      expect(r.end, truncatedToday.add(const Duration(days: 1)));
      expect(r.start, truncatedToday.subtract(const Duration(days: 6)));
    });

    test('dayCount matches resolve().end - resolve().start', () {
      final r = ReportsRange.lastNDays(30);
      expect(r.dayCount, 30);
      final r2 = ReportsRange.custom(
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 31),
      );
      // Jan 1 → Apr 1 exclusive = 90 days
      expect(r2.dayCount, 90);
    });

    test('describe() includes day count and date range', () {
      final r = ReportsRange.month(DateTime(2026, 9));
      final text = r.describe();
      expect(text, contains('30 days'));
      expect(text, contains('2026-09-01'));
      expect(text, contains('2026-09-30'));
    });

    test('describe() for lastNDays ends today', () {
      final r = ReportsRange.lastNDays(7);
      final text = r.describe();
      expect(text, contains('7 days'));
    });
  });
}
