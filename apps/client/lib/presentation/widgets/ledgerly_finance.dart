import 'package:flutter/material.dart';

import '../../data/ledger_repository.dart';
import '../../domain/default_categories.dart';
import '../design/ledgerly_theme.dart';

String localizedLedgerName(String? name) {
  if (name == null || name.isEmpty) return '未分类';
  final defaultName = localizedDefaultCategoryName(name);
  if (defaultName != null) return defaultName;
  return switch (name) {
    'Cash' => '现金',
    'Bank' => '银行卡',
    'Transfer' => '账户转账',
    'Other' => '其他',
    final value => value,
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
    'Meals' || '日常用餐' => Icons.rice_bowl_outlined,
    'Drinks & Snacks' || '饮品零食' => Icons.local_cafe_outlined,
    'Transport' || '交通' => Icons.directions_bus_outlined,
    'Public Transport' || '公交地铁' => Icons.directions_subway_outlined,
    'Taxi' || '网约车' => Icons.local_taxi_outlined,
    'Car Expenses' || '驾车养车' => Icons.directions_car_outlined,
    'Shopping' || '购物' => Icons.shopping_bag_outlined,
    'Daily Essentials' || '日用百货' => Icons.shopping_cart_outlined,
    'Clothing' || '服饰美妆' => Icons.checkroom_outlined,
    'Electronics' || '数码电器' => Icons.devices_outlined,
    'Housing' || '居住' => Icons.home_outlined,
    'Rent & Mortgage' || '房租房贷' => Icons.apartment_outlined,
    'Utilities' || '水电燃气' => Icons.bolt_outlined,
    'Property Services' || '物业家政' => Icons.home_repair_service_outlined,
    'Leisure' || '休闲' => Icons.weekend_outlined,
    'Entertainment' || '娱乐' => Icons.movie_outlined,
    'Fitness' || '运动健身' => Icons.fitness_center_outlined,
    'Travel' || '旅行' => Icons.luggage_outlined,
    'Healthcare' || '医疗健康' => Icons.health_and_safety_outlined,
    'Medical Care' || '看病就医' => Icons.local_hospital_outlined,
    'Medicine' || '药品保健' => Icons.medication_outlined,
    'Education' || '学习' => Icons.school_outlined,
    'Books' || '书籍' => Icons.menu_book_outlined,
    'Courses' || '课程培训' => Icons.cast_for_education_outlined,
    'Other Expense' || '其他支出' => Icons.more_horiz_rounded,
    'Salary' || '工资收入' => Icons.work_outline_rounded,
    'Base Salary' || '基本工资' => Icons.badge_outlined,
    'Bonus' || '奖金' => Icons.redeem_outlined,
    'Side Income' || '副业收入' => Icons.business_center_outlined,
    'Freelance' || '自由职业' => Icons.laptop_mac_outlined,
    'Business Income' || '经营收入' => Icons.storefront_outlined,
    'Investment Income' || '投资收益' => Icons.trending_up_rounded,
    'Interest' || '利息' => Icons.savings_outlined,
    'Dividends' || '分红' => Icons.pie_chart_outline_rounded,
    'Other Income' || '其他收入' => Icons.add_chart_outlined,
    _ => Icons.receipt_long_outlined,
  };
}

Color ledgerColorFor(String? name, {TransactionSummaryKind? kind}) {
  if (kind == TransactionSummaryKind.income) return LedgerlyColors.income;
  if (kind == TransactionSummaryKind.transfer) return LedgerlyColors.chartBlue;
  return switch (name) {
    'Food' ||
    '餐饮' ||
    'Meals' ||
    '日常用餐' ||
    'Drinks & Snacks' ||
    '饮品零食' =>
      LedgerlyColors.actionStrong,
    'Transport' ||
    '交通' ||
    'Public Transport' ||
    '公交地铁' ||
    'Taxi' ||
    '网约车' ||
    'Car Expenses' ||
    '驾车养车' =>
      LedgerlyColors.chartBlue,
    'Salary' ||
    '工资收入' ||
    'Base Salary' ||
    '基本工资' ||
    'Bonus' ||
    '奖金' =>
      LedgerlyColors.income,
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
