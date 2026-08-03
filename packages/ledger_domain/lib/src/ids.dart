final class BookId {
  const BookId(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is BookId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

final class AccountId {
  const AccountId(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is AccountId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

final class TransactionId {
  const TransactionId(this.value);
  final String value;
  @override
  bool operator ==(Object other) =>
      other is TransactionId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

final class EntryId {
  const EntryId(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is EntryId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}
