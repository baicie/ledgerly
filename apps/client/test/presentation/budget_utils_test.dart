import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/presentation/pages/budgets_page.dart';

void main() {
  test('parses yuan amounts into minor units', () {
    expect(parseBudgetAmountMinor('2,000.5'), BigInt.from(200050));
    expect(parseBudgetAmountMinor('0.01'), BigInt.one);
  });

  test('rejects invalid or non-positive budget amounts', () {
    expect(parseBudgetAmountMinor(''), isNull);
    expect(parseBudgetAmountMinor('0'), isNull);
    expect(parseBudgetAmountMinor('-1'), isNull);
    expect(parseBudgetAmountMinor('12.345'), isNull);
  });
}
