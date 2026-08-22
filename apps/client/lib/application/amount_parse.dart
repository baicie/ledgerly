BigInt? parsePositiveAmountMinor(String raw) {
  final value = raw.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final yuan = BigInt.tryParse(parts[0]);
  if (yuan == null) return null;
  final cents = parts.length == 1
      ? BigInt.zero
      : BigInt.tryParse(parts[1].padRight(2, '0'));
  if (cents == null) return null;
  final amount = yuan * BigInt.from(100) + cents;
  return amount > BigInt.zero ? amount : null;
}
