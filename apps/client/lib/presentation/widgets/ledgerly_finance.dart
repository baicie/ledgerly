import 'package:flutter/material.dart';

import '../../data/ledger_repository.dart';
import '../design/ledgerly_theme.dart';

String localizedLedgerName(String? name) {
  return switch (name) {
    'Cash' => '现金',
    'Bank' => '银行卡',
    'Food' => '餐饮',
    'Transport' => '交通',
    'Salary' => '工资收入',
    'Transfer' => '账户转账',
    'Other' => '其他',
    final value? when value.isNotEmpty => value,
    _ => '未分类',
  };
}

String formatDisplayMinor(BigInt minor, {bool symbol = true}) {
  final negative = minor.isNegative;
  final abs = minor.abs();
  final yuan = (abs ~/ BigInt.from(100)).toString();
  final cents = (abs % BigInt.from(100)).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var index = 0; index < yuan.length; index++) {
    if (index > 0 && (yuan.length - index) % 3 == 0) buffer.write(',');
    buffer.write(yuan[index]);
  }
  return '${negative ? '-' : ''}${symbol ? '¥' : ''}${buffer.toString()}.$cents';
}

IconData ledgerIconFor(String? name, {TransactionSummaryKind? kind}) {
  if (kind == TransactionSummaryKind.transfer) return Icons.swap_horiz_rounded;
  return switch (name) {
    'Cash' => Icons.payments_outlined,
    'Bank' => Icons.account_balance_outlined,
    'Food' || '餐饮' => Icons.restaurant_outlined,
    'Transport' || '交通' => Icons.directions_bus_outlined,
    'Salary' || '工资收入' => Icons.work_outline_rounded,
    _ => Icons.receipt_long_outlined,
  };
}

Color ledgerColorFor(String? name, {TransactionSummaryKind? kind}) {
  if (kind == TransactionSummaryKind.income) return LedgerlyColors.income;
  if (kind == TransactionSummaryKind.transfer) return LedgerlyColors.chartBlue;
  return switch (name) {
    'Food' || '餐饮' => LedgerlyColors.actionStrong,
    'Transport' || '交通' => LedgerlyColors.chartBlue,
    'Salary' || '工资收入' => LedgerlyColors.income,
    'Cash' => LedgerlyColors.warning,
    _ => LedgerlyColors.expense,
  };
}

class LedgerlyIconBadge extends StatelessWidget {
  const LedgerlyIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class LedgerlyProgressRow extends StatelessWidget {
  const LedgerlyProgressRow({
    super.key,
    required this.rank,
    required this.name,
    required this.amount,
    required this.fraction,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final int rank;
  final String name;
  final String? subtitle;
  final BigInt amount;
  final double fraction;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child:
                  Text('$rank', style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          LedgerlyIconBadge(icon: icon, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Text(
                      '${(fraction * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDisplayMinor(amount, symbol: false),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0, 1),
                    minHeight: 4,
                    color: color,
                    backgroundColor: LedgerlyColors.divider,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
