final class CurrencyCode {
  factory CurrencyCode.parse(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw FormatException('Invalid currency code: $raw');
    }
    return CurrencyCode._(normalized);
  }

  const CurrencyCode._(this.value);

  final String value;

  static const cny = CurrencyCode._('CNY');
  static const usd = CurrencyCode._('USD');
  static const jpy = CurrencyCode._('JPY');

  @override
  bool operator ==(Object other) =>
      other is CurrencyCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
