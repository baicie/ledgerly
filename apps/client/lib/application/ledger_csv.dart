import '../data/ledger_repository.dart';
import '../l10n/l10n.dart';
import '../presentation/widgets/ledgerly_finance.dart';

String csvKindLabel(TransactionSummaryKind kind) {
  return switch (kind) {
    TransactionSummaryKind.expense => 'expense',
    TransactionSummaryKind.income => 'income',
    TransactionSummaryKind.transfer => 'transfer',
    TransactionSummaryKind.adjustment => 'adjustment',
  };
}

String buildLedgerCsv(
  Iterable<TransactionSummary> transactions, {
  AppLocalizations? l10n,
}) {
  final buf = StringBuffer('\uFEFFdate,kind,amount,category,account,description\n');
  for (final tx in transactions) {
    final category = l10n == null
        ? (tx.categoryName ?? '')
        : localizedLedgerName(l10n, tx.categoryName);
    final account = l10n == null
        ? (tx.accountName ?? '')
        : localizedLedgerName(l10n, tx.accountName);
    buf.writeln(
      [
        tx.occurredAt.toLocal().toIso8601String(),
        csvKindLabel(tx.kind),
        formatDisplayMinor(tx.amountMinor, symbol: false),
        _csvEscape(category),
        _csvEscape(account),
        _csvEscape(tx.description ?? ''),
      ].join(','),
    );
  }
  return buf.toString();
}

String _csvEscape(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
