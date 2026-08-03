enum DomainErrorCode {
  zeroAmount,
  unbalanced,
  tooFewEntries,
  currencyMismatch,
  invalidTransfer,
  invalidAccount,
}

final class DomainException implements Exception {
  const DomainException(this.code, this.message);
  final DomainErrorCode code;
  final String message;

  @override
  String toString() => 'DomainException($code): $message';
}
