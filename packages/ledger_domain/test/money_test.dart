import 'package:ledger_domain/ledger_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('rejects zero', () {
      expect(
        () => Money.fromMinorInt(0, CurrencyCode.cny),
        throwsA(
          isA<DomainException>().having(
            (e) => e.code,
            'code',
            DomainErrorCode.zeroAmount,
          ),
        ),
      );
    });

    test('negation flips sign', () {
      final m = Money.fromMinorInt(1234, CurrencyCode.cny);
      expect((-m).minorUnits, equals(BigInt.from(-1234)));
    });

    test('large minor units accepted', () {
      final huge = BigInt.parse('9223372036854775807'); // i64 max
      final m = Money(minorUnits: huge, currency: CurrencyCode.usd);
      expect(m.minorUnits, huge);
    });
  });

  group('CurrencyCode', () {
    test('parses uppercase', () {
      expect(CurrencyCode.parse('cny').value, 'CNY');
    });

    test('rejects invalid', () {
      expect(() => CurrencyCode.parse('CN'), throwsFormatException);
    });
  });
}
