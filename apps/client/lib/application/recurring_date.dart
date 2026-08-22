class RecurringDate {
  RecurringDate._();

  static String format(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static DateTime parse(String value) {
    final parts = value.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static int daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  static int clampDay(int year, int month, int dayOfMonth) {
    final wanted = dayOfMonth.clamp(1, 31);
    final last = daysInMonth(year, month);
    return wanted > last ? last : wanted;
  }

  static String nextMonthlyDate({
    required DateTime from,
    required int dayOfMonth,
  }) {
    final wanted = dayOfMonth.clamp(1, 31);
    var year = from.year;
    var month = from.month;
    final thisMonthDay = clampDay(year, month, wanted);
    if (from.day > thisMonthDay) {
      month += 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
    }
    return format(DateTime(year, month, clampDay(year, month, wanted)));
  }

  static String advanceOneMonth(String current, int dayOfMonth) {
    final date = parse(current);
    var year = date.year;
    var month = date.month + 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
    return format(DateTime(year, month, clampDay(year, month, dayOfMonth)));
  }

  static bool isDue(String nextRunDate, DateTime now) {
    return !parse(nextRunDate).isAfter(
      DateTime(now.year, now.month, now.day),
    );
  }
}
