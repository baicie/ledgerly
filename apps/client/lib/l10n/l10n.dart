import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

class L10n {
  static Locale locale = const Locale('zh');

  static AppLocalizations get current =>
      lookupAppLocalizations(canonical(locale));

  static Locale canonical(Locale locale) {
    if (locale.languageCode == 'en') return const Locale('en');
    return const Locale('zh');
  }

  static Locale resolve(Locale? locale, Iterable<Locale> supported) {
    final resolved = canonical(locale ?? const Locale('zh'));
    L10n.locale = resolved;
    return resolved;
  }
}

AppLocalizations l10nOf(BuildContext context) {
  return AppLocalizations.of(context) ??
      lookupAppLocalizations(const Locale('zh'));
}

String localizedLedgerName(AppLocalizations l10n, String? name) {
  if (name == null || name.isEmpty) return l10n.uncategorized;
  return switch (name) {
    'Cash' || '现金' => l10n.accountCash,
    'Bank' || '银行卡' => l10n.accountBank,
    'Transfer' || '账户转账' => l10n.accountTransfer,
    'Other' || '其他' => l10n.accountOther,
    'Food' || '餐饮' => l10n.categoryFood,
    'Meals' || '日常用餐' => l10n.categoryMeals,
    'Drinks & Snacks' || '饮品零食' => l10n.categoryDrinksSnacks,
    'Transport' || '交通' => l10n.categoryTransport,
    'Public Transport' || '公交地铁' => l10n.categoryPublicTransport,
    'Taxi' || '网约车' => l10n.categoryTaxi,
    'Car Expenses' || '驾车养车' => l10n.categoryCarExpenses,
    'Shopping' || '购物' => l10n.categoryShopping,
    'Daily Essentials' || '日用百货' => l10n.categoryDailyEssentials,
    'Clothing' || '服饰美妆' => l10n.categoryClothing,
    'Electronics' || '数码电器' => l10n.categoryElectronics,
    'Housing' || '居住' => l10n.categoryHousing,
    'Rent & Mortgage' || '房租房贷' => l10n.categoryRentMortgage,
    'Utilities' || '水电燃气' => l10n.categoryUtilities,
    'Property Services' || '物业家政' => l10n.categoryPropertyServices,
    'Leisure' || '休闲' => l10n.categoryLeisure,
    'Entertainment' || '娱乐' => l10n.categoryEntertainment,
    'Fitness' || '运动健身' => l10n.categoryFitness,
    'Travel' || '旅行' => l10n.categoryTravel,
    'Healthcare' || '医疗健康' => l10n.categoryHealthcare,
    'Medical Care' || '看病就医' => l10n.categoryMedicalCare,
    'Medicine' || '药品保健' => l10n.categoryMedicine,
    'Education' || '学习' => l10n.categoryEducation,
    'Books' || '书籍' => l10n.categoryBooks,
    'Courses' || '课程培训' => l10n.categoryCourses,
    'Other Expense' || '其他支出' => l10n.categoryOtherExpense,
    'Salary' || '工资收入' => l10n.categorySalary,
    'Base Salary' || '基本工资' => l10n.categoryBaseSalary,
    'Bonus' || '奖金' => l10n.categoryBonus,
    'Side Income' || '副业收入' => l10n.categorySideIncome,
    'Freelance' || '自由职业' => l10n.categoryFreelance,
    'Business Income' || '经营收入' => l10n.categoryBusinessIncome,
    'Investment Income' || '投资收益' => l10n.categoryInvestmentIncome,
    'Interest' || '利息' => l10n.categoryInterest,
    'Dividends' || '分红' => l10n.categoryDividends,
    'Other Income' || '其他收入' => l10n.categoryOtherIncome,
    final value => value,
  };
}

String weekdayLabel(AppLocalizations l10n, int weekday) {
  return switch (weekday) {
    1 => l10n.weekdayMon,
    2 => l10n.weekdayTue,
    3 => l10n.weekdayWed,
    4 => l10n.weekdayThu,
    5 => l10n.weekdayFri,
    6 => l10n.weekdaySat,
    _ => l10n.weekdaySun,
  };
}

String insightKindLabel(AppLocalizations l10n, String kindName) {
  return switch (kindName) {
    'daily' => l10n.insightKindDaily,
    'monthly' => l10n.insightKindMonthly,
    _ => kindName,
  };
}

String insightPeriodLabel({
  required AppLocalizations l10n,
  required String kindName,
  String? periodKey,
  String? fallback,
}) {
  if (fallback != null && fallback.isNotEmpty) return fallback;
  if (periodKey == null || periodKey.isEmpty) return '';
  final parts = periodKey.split('-');
  if (kindName == 'daily' && parts.length >= 3) {
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year != null && month != null && day != null) {
      return l10n.insightDailyDate(year, month, day);
    }
  }
  if (kindName == 'monthly' && parts.length >= 2) {
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year != null && month != null) {
      return l10n.insightMonthlyDate(year, month);
    }
  }
  return periodKey;
}
