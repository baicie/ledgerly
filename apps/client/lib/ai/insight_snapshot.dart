import 'dart:convert';

import '../data/ledger_repository.dart';
import '../domain/default_categories.dart';
import 'insight_period.dart';

class InsightSnapshot {
  const InsightSnapshot({
    required this.period,
    required this.payload,
    required this.hash,
    required this.transactionCount,
    required this.hasActivity,
  });

  final InsightPeriod period;
  final Map<String, Object?> payload;
  final String hash;
  final int transactionCount;
  final bool hasActivity;

  String get userPrompt => const JsonEncoder.withIndent('  ').convert(payload);
}

InsightSnapshot buildInsightSnapshot({
  required InsightPeriod period,
  required List<TransactionSummary> transactions,
  String currency = 'CNY',
}) {
  final relevant = [
    for (final transaction in transactions)
      if (transaction.kind != TransactionSummaryKind.adjustment) transaction,
  ]..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));

  var income = BigInt.zero;
  var expense = BigInt.zero;
  var incomeCount = 0;
  var expenseCount = 0;
  final expenseByCategory = <String, _CategoryBucket>{};
  final incomeByCategory = <String, _CategoryBucket>{};

  for (final transaction in relevant) {
    switch (transaction.kind) {
      case TransactionSummaryKind.income:
        income += transaction.amountMinor;
        incomeCount += 1;
        _addCategory(incomeByCategory, transaction);
      case TransactionSummaryKind.expense:
        expense += transaction.amountMinor;
        expenseCount += 1;
        _addCategory(expenseByCategory, transaction);
      case TransactionSummaryKind.transfer:
      case TransactionSummaryKind.adjustment:
        break;
    }
  }

  const detailLimit = 80;
  final truncated = relevant.length > detailLimit;
  final details = truncated
      ? (List<TransactionSummary>.from(relevant)
            ..sort(
              (left, right) => right.amountMinor.compareTo(left.amountMinor),
            ))
          .take(detailLimit)
          .toList()
      : relevant;

  final payload = <String, Object?>{
    'period': {
      'kind': period.kind.name,
      'key': period.key,
      'label': period.label,
    },
    'currency': currency,
    'totals': {
      'income': formatInsightYuan(income),
      'expense': formatInsightYuan(expense),
      'income_count': incomeCount,
      'expense_count': expenseCount,
      'transaction_count': relevant.length,
    },
    'expense_by_category': _encodeBuckets(expenseByCategory),
    'income_by_category': _encodeBuckets(incomeByCategory),
    'transactions': [
      for (final transaction in details) _encodeTransaction(transaction),
    ],
    if (truncated) 'transactions_truncated': true,
  };

  return InsightSnapshot(
    period: period,
    payload: payload,
    hash: jsonEncode(payload),
    transactionCount: relevant.length,
    hasActivity: relevant.isNotEmpty,
  );
}

String formatInsightYuan(BigInt minor) {
  final negative = minor.isNegative;
  final abs = minor.abs();
  final yuan = abs ~/ BigInt.from(100);
  final cents = (abs % BigInt.from(100)).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$yuan.$cents';
}

void _addCategory(
  Map<String, _CategoryBucket> buckets,
  TransactionSummary transaction,
) {
  final name = _categoryLabel(transaction.categoryName);
  final bucket = buckets.putIfAbsent(name, _CategoryBucket.new);
  bucket.amount += transaction.amountMinor;
  bucket.count += 1;
}

List<Map<String, Object?>> _encodeBuckets(
  Map<String, _CategoryBucket> buckets,
) {
  final rows = buckets.entries.toList()
    ..sort((left, right) => right.value.amount.compareTo(left.value.amount));
  return [
    for (final entry in rows)
      {
        'name': entry.key,
        'amount': formatInsightYuan(entry.value.amount),
        'count': entry.value.count,
      },
  ];
}

Map<String, Object?> _encodeTransaction(TransactionSummary transaction) {
  final local = transaction.occurredAt.toLocal();
  final note = transaction.description?.trim() ?? '';
  return {
    'time':
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    'kind': transaction.kind.name,
    'amount': formatInsightYuan(transaction.amountMinor),
    'category': _categoryLabel(transaction.categoryName),
    if (note.isNotEmpty)
      'note': note.length <= 40 ? note : note.substring(0, 40),
  };
}

String _categoryLabel(String? name) {
  return localizedDefaultCategoryName(name ?? '') ?? localizedInsightName(name);
}

class _CategoryBucket {
  BigInt amount = BigInt.zero;
  int count = 0;
}
