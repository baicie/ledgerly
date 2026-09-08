import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Time range used by the Reports page.
///
/// The default `month` mode corresponds to the current calendar month and
/// preserves the original ReportsPage UX. Multi-month and year modes
/// aggregate summary metrics across the range; the trend chart always
/// returns one point per month inside the range.
enum ReportsRangeKind {
  month,
  last3Months,
  last6Months,
  year,
  last7Days,
  last30Days,
  last90Days,
  custom,
}

class ReportsRange {
  ReportsRange({
    required this.kind,
    DateTime? anchor,
    this.customStart,
    this.customEnd,
  }) : anchor = anchor ?? _nowMonth();

  final ReportsRangeKind kind;
  final DateTime anchor;
  final DateTime? customStart;
  final DateTime? customEnd;

  factory ReportsRange.month([DateTime? anchor]) =>
      ReportsRange(kind: ReportsRangeKind.month, anchor: anchor);

  factory ReportsRange.last3Months([DateTime? anchor]) =>
      ReportsRange(kind: ReportsRangeKind.last3Months, anchor: anchor);

  factory ReportsRange.last6Months([DateTime? anchor]) =>
      ReportsRange(kind: ReportsRangeKind.last6Months, anchor: anchor);

  factory ReportsRange.year([DateTime? anchor]) =>
      ReportsRange(kind: ReportsRangeKind.year, anchor: anchor);

  factory ReportsRange.lastNDays(int days, [DateTime? anchor]) {
    if (days == 7) return ReportsRange(kind: ReportsRangeKind.last7Days, anchor: anchor);
    if (days == 30) return ReportsRange(kind: ReportsRangeKind.last30Days, anchor: anchor);
    if (days == 90) return ReportsRange(kind: ReportsRangeKind.last90Days, anchor: anchor);
    throw ArgumentError.value(days, 'days', 'Only 7/30/90 supported');
  }

  factory ReportsRange.custom(DateTime start, DateTime end) => ReportsRange(
        kind: ReportsRangeKind.custom,
        customStart: _truncate(start),
        customEnd: _truncate(end),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportsRange &&
        other.kind == kind &&
        other.anchor == anchor &&
        other.customStart == customStart &&
        other.customEnd == customEnd;
  }

  @override
  int get hashCode => Object.hash(kind, anchor, customStart, customEnd);

  @override
  String toString() =>
      'ReportsRange(kind: $kind, anchor: $anchor, customStart: $customStart, customEnd: $customEnd)';

  /// Returns the inclusive start (midnight) and exclusive end (midnight of
  /// the day after the range) of the range. For monthly anchors the end
  /// is the first day of the *next* month.
  ({DateTime start, DateTime end}) resolve() {
    switch (kind) {
      case ReportsRangeKind.month:
        final a = anchor;
        return (
          start: DateTime(a.year, a.month),
          end: DateTime(a.year, a.month + 1),
        );
      case ReportsRangeKind.last3Months:
        final a = anchor;
        final start = DateTime(a.year, a.month - 2);
        return (
          start: start,
          end: DateTime(a.year, a.month + 1),
        );
      case ReportsRangeKind.last6Months:
        final a = anchor;
        final start = DateTime(a.year, a.month - 5);
        return (
          start: start,
          end: DateTime(a.year, a.month + 1),
        );
      case ReportsRangeKind.year:
        return (
          start: DateTime(anchor.year, 1),
          end: DateTime(anchor.year + 1, 1),
        );
      case ReportsRangeKind.last7Days:
      case ReportsRangeKind.last30Days:
      case ReportsRangeKind.last90Days:
        final today = _truncate(DateTime.now());
        final days = kind == ReportsRangeKind.last7Days
            ? 7
            : kind == ReportsRangeKind.last30Days
                ? 30
                : 90;
        return (
          start: today.subtract(Duration(days: days - 1)),
          end: today.add(const Duration(days: 1)),
        );
      case ReportsRangeKind.custom:
        final s = customStart ?? _nowMonth();
        final e = customEnd ?? s;
        final endNext = DateTime(e.year, e.month + 1);
        return (start: _truncate(s), end: endNext);
    }
  }

  /// Number of months covered by this range. Used by the trend provider
  /// to know how many points to fetch.
  int get monthCount {
    switch (kind) {
      case ReportsRangeKind.month:
        return 1;
      case ReportsRangeKind.last3Months:
        return 3;
      case ReportsRangeKind.last6Months:
        return 6;
      case ReportsRangeKind.year:
        return 12;
      case ReportsRangeKind.last7Days:
        return 1;
      case ReportsRangeKind.last30Days:
        return 1;
      case ReportsRangeKind.last90Days:
        return 3;
      case ReportsRangeKind.custom:
        final r = resolve();
        final start = r.start;
        final end = r.end;
        if (!end.isAfter(start)) return 1;
        return ((end.year - start.year) * 12 + end.month - start.month)
            .clamp(1, 60);
    }
  }

  bool get isMultiMonth => monthCount > 1;

  /// True when a monthly anchor shift makes sense.
  bool get isMonthAnchored =>
      kind == ReportsRangeKind.month ||
      kind == ReportsRangeKind.last3Months ||
      kind == ReportsRangeKind.last6Months;

  /// Number of calendar days covered by this range. Used for labels and
  /// quick preset matching. Always at least 1.
  int get dayCount {
    final r = resolve();
    final start = r.start;
    final end = r.end;
    if (!end.isAfter(start)) return 1;
    return end.difference(start).inDays;
  }

  /// Localized human-friendly description of this range, including start
  /// and end dates and the total day count. Used by the picker to preview
  /// what a chosen preset will look like.
  String describe() {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = resolve();
    final days = dayCount;
    switch (kind) {
      case ReportsRangeKind.month:
        final a = anchor;
        return '$days days · ${fmt(DateTime(a.year, a.month, 1))} → ${fmt(DateTime(a.year, a.month + 1, 0))}';
      case ReportsRangeKind.last3Months:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime(anchor.year, anchor.month + 1, 0))}';
      case ReportsRangeKind.last6Months:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime(anchor.year, anchor.month + 1, 0))}';
      case ReportsRangeKind.year:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime(anchor.year, 12, 31))}';
      case ReportsRangeKind.last7Days:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime.now())}';
      case ReportsRangeKind.last30Days:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime.now())}';
      case ReportsRangeKind.last90Days:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime.now())}';
      case ReportsRangeKind.custom:
        return '$days days · ${fmt(r.start)} → ${fmt(DateTime(customEnd!.year, customEnd!.month, customEnd!.day))}';
    }
  }

  ReportsRange withAnchor(DateTime next) {
    if (!isMonthAnchored) return this;
    return ReportsRange(kind: kind, anchor: next);
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'anchor': anchor.toIso8601String(),
        'customStart': customStart?.toIso8601String(),
        'customEnd': customEnd?.toIso8601String(),
      };

  factory ReportsRange.fromJson(Map<String, dynamic> json) {
    final kind = ReportsRangeKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ReportsRangeKind.month,
    );
    return ReportsRange(
      kind: kind,
      anchor: json['anchor'] != null
          ? DateTime.tryParse(json['anchor'].toString()) ?? _nowMonth()
          : _nowMonth(),
      customStart: json['customStart'] != null
          ? DateTime.tryParse(json['customStart'].toString())
          : null,
      customEnd: json['customEnd'] != null
          ? DateTime.tryParse(json['customEnd'].toString())
          : null,
    );
  }

  static DateTime _nowMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  static DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);
}

const _prefsKey = 'ledgerly.reports.range.v1';

/// Persists [ReportsRange] to [SharedPreferences] as JSON.
class ReportsRangeStore {
  ReportsRangeStore({Future<SharedPreferences>? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance();

  factory ReportsRangeStore.inMemory() => ReportsRangeStore();

  final Future<SharedPreferences>? _preferences;

  Future<ReportsRange?> read() async {
    final prefs = await _preferences;
    if (prefs == null) return null;
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ReportsRange.fromJson(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(ReportsRange range) async {
    final prefs = await _preferences;
    if (prefs == null) return;
    await prefs.setString(_prefsKey, jsonEncode(range.toJson()));
  }
}

