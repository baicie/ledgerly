import '../presentation/providers.dart';

/// Generates export artifacts (CSV, plain-text summary) from report data.
class ReportCsvFormatter {
  ReportCsvFormatter({
    required this.summary,
    required this.trend,
    required this.rangeLabel,
    required this.currency,
  });

  final ReportSummary summary;
  final List<ReportTrendPoint> trend;
  final String rangeLabel;
  final String currency;

  /// Builds a UTF-8 CSV with three sections:
  /// 1. Summary (income, expense, net)
  /// 2. Categories (name, amount)
  /// 3. Monthly trend (month, income, expense, net)
  String toCsv() {
    String minorToUnit(BigInt v) =>
        (int.parse(v.toString()) / 100).toStringAsFixed(2);

    final buf = StringBuffer();

    // Header
    buf.writeln('# Ledgerly Report — $rangeLabel');
    buf.writeln('# Generated: ${_iso(DateTime.now())}');
    buf.writeln();

    // Summary section
    buf.writeln('# Summary');
    buf.writeln('Income ($currency),Expense ($currency),Net ($currency),Currency');
    buf.writeln(
        '${minorToUnit(summary.incomeMinor)},${minorToUnit(summary.expenseMinor)},${minorToUnit(summary.netMinor)},$currency');
    buf.writeln();

    // Categories section (only for single-month view)
    if (summary.categories.isNotEmpty) {
      buf.writeln('# Categories');
      buf.writeln('Category,Amount ($currency)');
      for (final c in summary.categories) {
        buf.writeln('"${_escape(c.name)}",${minorToUnit(c.amountMinor)}');
      }
      buf.writeln();
    }

    // Trend section
    if (trend.isNotEmpty) {
      buf.writeln('# Monthly Trend');
      buf.writeln('Month,Income ($currency),Expense ($currency),Net ($currency)');
      for (final p in trend) {
        buf.writeln(
            '${p.month},${minorToUnit(p.incomeMinor)},${minorToUnit(p.expenseMinor)},${minorToUnit(p.netMinor)}');
      }
    }

    return buf.toString();
  }

  /// Builds a plain-text summary suitable for sharing via the system share
  /// sheet. Uses emoji and a compact layout.
  String toShareText() {
    String minorToUnit(BigInt v) =>
        (int.parse(v.toString()) / 100).toStringAsFixed(2);
    String fmt(BigInt v) => '$currency ${minorToUnit(v)}';

    final lines = <String>[];

    lines.add('📊 $rangeLabel 账单摘要');
    lines.add('─────────────────');
    lines.add('💰 收入  ${fmt(summary.incomeMinor)}');
    lines.add('💸 支出  ${fmt(summary.expenseMinor)}');
    lines.add('📈 净额  ${fmt(summary.netMinor)}');

    if (summary.categories.isNotEmpty) {
      lines.add('─────────────────');
      lines.add('📁 支出类别 TOP:');
      for (final c in summary.categories.take(5)) {
        lines.add('  • ${c.name}: ${fmt(c.amountMinor)}');
      }
    }

    if (trend.isNotEmpty) {
      lines.add('─────────────────');
      lines.add('📆 近 ${trend.length} 月趋势');
      for (final p in trend.reversed.take(3)) {
        lines.add(
            '  ${p.month}  收入 ${minorToUnit(p.incomeMinor)}  支出 ${minorToUnit(p.expenseMinor)}');
      }
    }

    lines.add('─────────────────');
    lines.add('via Ledgerly');
    return lines.join('\n');
  }

  String _escape(String s) => s.replaceAll('"', '""');

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
