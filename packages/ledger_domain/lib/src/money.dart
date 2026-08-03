import 'currency.dart';
import 'errors.dart';

/// Monetary amount in integer minor units (never floating point).
final class Money {
  Money({required BigInt minorUnits, required this.currency})
      : minorUnits = minorUnits {
    if (minorUnits == BigInt.zero) {
      throw const DomainException(
        DomainErrorCode.zeroAmount,
        'Money amount must be non-zero',
      );
    }
  }

  factory Money.fromMinorInt(int minorUnits, CurrencyCode currency) =>
      Money(minorUnits: BigInt.from(minorUnits), currency: currency);

  final BigInt minorUnits;
  final CurrencyCode currency;

  Money operator -() => Money(minorUnits: -minorUnits, currency: currency);

  Money operator +(Money other) {
    _sameCurrency(other);
    final sum = minorUnits + other.minorUnits;
    if (sum == BigInt.zero) {
      throw const DomainException(
        DomainErrorCode.zeroAmount,
        'Sum would be zero; use balanced entries instead',
      );
    }
    return Money(minorUnits: sum, currency: currency);
  }

  void _sameCurrency(Money other) {
    if (currency != other.currency) {
      throw DomainException(
        DomainErrorCode.currencyMismatch,
        'Currency mismatch: $currency vs ${other.currency}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '$minorUnits $currency';
}
