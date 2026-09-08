import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/report_csv_formatter.dart';
import 'package:ledgerly_client/presentation/providers.dart';

void main() {
  ReportSummary makeSummary({
    BigInt? income,
    BigInt? expense,
    List<ReportCategory>? categories,
  }) {
    final inc = income ?? BigInt.from(100000);
    final exp = expense ?? BigInt.from(50000);
    return ReportSummary(
      incomeMinor: inc,
      expenseMinor: exp,
      netMinor: inc - exp,
      baseCurrency: 'CNY',
      categories: categories ?? const [],
      plan: 'test',
    );
  }

  group('ReportCsvFormatter', () {
    test('toCsv includes summary section', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(),
        trend: const [],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final csv = formatter.toCsv();
      expect(csv, contains('# Summary'));
      expect(csv, contains('Income (CNY),Expense (CNY),Net (CNY),Currency'));
      expect(csv, contains('1000.00,500.00,500.00,CNY'));
    });

    test('toCsv includes categories when present', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(
          categories: [
            ReportCategory(
              name: 'Food',
              amountMinor: BigInt.from(20000),
              currency: 'CNY',
            ),
          ],
        ),
        trend: const [],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final csv = formatter.toCsv();
      expect(csv, contains('# Categories'));
      expect(csv, contains('Category,Amount (CNY)'));
      expect(csv, contains('"Food",200.00'));
    });

    test('toCsv escapes category names with quotes', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(
          categories: [
            ReportCategory(
              name: 'Food, Inc.',
              amountMinor: BigInt.from(10000),
              currency: 'CNY',
            ),
          ],
        ),
        trend: const [],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final csv = formatter.toCsv();
      expect(csv, contains('"Food, Inc."'));
    });

    test('toCsv includes trend section', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(),
        trend: [
          ReportTrendPoint(
            month: '2026-07',
            incomeMinor: BigInt.from(80000),
            expenseMinor: BigInt.from(40000),
            netMinor: BigInt.from(40000),
          ),
        ],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final csv = formatter.toCsv();
      expect(csv, contains('# Monthly Trend'));
      expect(csv, contains('2026-07'));
    });

    test('toShareText includes emoji summary', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(
          income: BigInt.from(100000),
          expense: BigInt.from(50000),
        ),
        trend: const [],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final text = formatter.toShareText();
      expect(text, contains('📊'));
      expect(text, contains('💰 收入'));
      expect(text, contains('💸 支出'));
      expect(text, contains('📈 净额'));
      expect(text, contains('1000.00'));
    });

    test('toShareText includes top categories', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(
          categories: [
            ReportCategory(
              name: 'Food',
              amountMinor: BigInt.from(20000),
              currency: 'CNY',
            ),
            ReportCategory(
              name: 'Transport',
              amountMinor: BigInt.from(10000),
              currency: 'CNY',
            ),
          ],
        ),
        trend: const [],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final text = formatter.toShareText();
      expect(text, contains('Food'));
      expect(text, contains('Transport'));
      expect(text, contains('📁'));
    });

    test('toShareText includes recent trend', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(),
        trend: [
          ReportTrendPoint(
            month: '2026-07',
            incomeMinor: BigInt.from(80000),
            expenseMinor: BigInt.from(40000),
            netMinor: BigInt.from(40000),
          ),
          ReportTrendPoint(
            month: '2026-08',
            incomeMinor: BigInt.from(90000),
            expenseMinor: BigInt.from(45000),
            netMinor: BigInt.from(45000),
          ),
        ],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final text = formatter.toShareText();
      expect(text, contains('📆'));
      expect(text, contains('2026-08'));
    });

    test('toShareText ends with via Ledgerly', () {
      final formatter = ReportCsvFormatter(
        summary: makeSummary(),
        trend: const [],
        rangeLabel: '2026-09',
        currency: 'CNY',
      );
      final text = formatter.toShareText();
      expect(text.trim(), endsWith('via Ledgerly'));
    });
  });
}
