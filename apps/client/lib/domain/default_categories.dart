class DefaultCategoryDefinition {
  const DefaultCategoryDefinition({
    required this.key,
    required this.name,
    required this.label,
    required this.type,
    this.parentKey,
  });

  final String key;
  final String name;
  final String label;
  final String type;
  final String? parentKey;

  bool get isRoot => parentKey == null;
}

const defaultCategoryDefinitions = <DefaultCategoryDefinition>[
  DefaultCategoryDefinition(
    key: 'acc_food',
    name: 'Food',
    label: '餐饮',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_food_meals',
    name: 'Meals',
    label: '日常用餐',
    type: 'expense',
    parentKey: 'acc_food',
  ),
  DefaultCategoryDefinition(
    key: 'acc_food_drinks',
    name: 'Drinks & Snacks',
    label: '饮品零食',
    type: 'expense',
    parentKey: 'acc_food',
  ),
  DefaultCategoryDefinition(
    key: 'acc_transport',
    name: 'Transport',
    label: '交通',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_transport_public',
    name: 'Public Transport',
    label: '公交地铁',
    type: 'expense',
    parentKey: 'acc_transport',
  ),
  DefaultCategoryDefinition(
    key: 'acc_transport_taxi',
    name: 'Taxi',
    label: '网约车',
    type: 'expense',
    parentKey: 'acc_transport',
  ),
  DefaultCategoryDefinition(
    key: 'acc_transport_car',
    name: 'Car Expenses',
    label: '驾车养车',
    type: 'expense',
    parentKey: 'acc_transport',
  ),
  DefaultCategoryDefinition(
    key: 'acc_shopping',
    name: 'Shopping',
    label: '购物',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_shopping_daily',
    name: 'Daily Essentials',
    label: '日用百货',
    type: 'expense',
    parentKey: 'acc_shopping',
  ),
  DefaultCategoryDefinition(
    key: 'acc_shopping_clothing',
    name: 'Clothing',
    label: '服饰美妆',
    type: 'expense',
    parentKey: 'acc_shopping',
  ),
  DefaultCategoryDefinition(
    key: 'acc_shopping_digital',
    name: 'Electronics',
    label: '数码电器',
    type: 'expense',
    parentKey: 'acc_shopping',
  ),
  DefaultCategoryDefinition(
    key: 'acc_housing',
    name: 'Housing',
    label: '居住',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_housing_rent',
    name: 'Rent & Mortgage',
    label: '房租房贷',
    type: 'expense',
    parentKey: 'acc_housing',
  ),
  DefaultCategoryDefinition(
    key: 'acc_housing_utilities',
    name: 'Utilities',
    label: '水电燃气',
    type: 'expense',
    parentKey: 'acc_housing',
  ),
  DefaultCategoryDefinition(
    key: 'acc_housing_property',
    name: 'Property Services',
    label: '物业家政',
    type: 'expense',
    parentKey: 'acc_housing',
  ),
  DefaultCategoryDefinition(
    key: 'acc_leisure',
    name: 'Leisure',
    label: '休闲',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_leisure_entertainment',
    name: 'Entertainment',
    label: '娱乐',
    type: 'expense',
    parentKey: 'acc_leisure',
  ),
  DefaultCategoryDefinition(
    key: 'acc_leisure_fitness',
    name: 'Fitness',
    label: '运动健身',
    type: 'expense',
    parentKey: 'acc_leisure',
  ),
  DefaultCategoryDefinition(
    key: 'acc_leisure_travel',
    name: 'Travel',
    label: '旅行',
    type: 'expense',
    parentKey: 'acc_leisure',
  ),
  DefaultCategoryDefinition(
    key: 'acc_healthcare',
    name: 'Healthcare',
    label: '医疗健康',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_healthcare_medical',
    name: 'Medical Care',
    label: '看病就医',
    type: 'expense',
    parentKey: 'acc_healthcare',
  ),
  DefaultCategoryDefinition(
    key: 'acc_healthcare_medicine',
    name: 'Medicine',
    label: '药品保健',
    type: 'expense',
    parentKey: 'acc_healthcare',
  ),
  DefaultCategoryDefinition(
    key: 'acc_education',
    name: 'Education',
    label: '学习',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_education_books',
    name: 'Books',
    label: '书籍',
    type: 'expense',
    parentKey: 'acc_education',
  ),
  DefaultCategoryDefinition(
    key: 'acc_education_courses',
    name: 'Courses',
    label: '课程培训',
    type: 'expense',
    parentKey: 'acc_education',
  ),
  DefaultCategoryDefinition(
    key: 'acc_other_expense',
    name: 'Other Expense',
    label: '其他支出',
    type: 'expense',
  ),
  DefaultCategoryDefinition(
    key: 'acc_salary',
    name: 'Salary',
    label: '工资收入',
    type: 'income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_salary_base',
    name: 'Base Salary',
    label: '基本工资',
    type: 'income',
    parentKey: 'acc_salary',
  ),
  DefaultCategoryDefinition(
    key: 'acc_salary_bonus',
    name: 'Bonus',
    label: '奖金',
    type: 'income',
    parentKey: 'acc_salary',
  ),
  DefaultCategoryDefinition(
    key: 'acc_side_income',
    name: 'Side Income',
    label: '副业收入',
    type: 'income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_side_income_freelance',
    name: 'Freelance',
    label: '自由职业',
    type: 'income',
    parentKey: 'acc_side_income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_side_income_business',
    name: 'Business Income',
    label: '经营收入',
    type: 'income',
    parentKey: 'acc_side_income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_investment_income',
    name: 'Investment Income',
    label: '投资收益',
    type: 'income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_investment_income_interest',
    name: 'Interest',
    label: '利息',
    type: 'income',
    parentKey: 'acc_investment_income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_investment_income_dividends',
    name: 'Dividends',
    label: '分红',
    type: 'income',
    parentKey: 'acc_investment_income',
  ),
  DefaultCategoryDefinition(
    key: 'acc_other_income',
    name: 'Other Income',
    label: '其他收入',
    type: 'income',
  ),
];

String? localizedDefaultCategoryName(String name) {
  final normalized = name.trim().toLowerCase();
  for (final category in defaultCategoryDefinitions) {
    if (category.name.toLowerCase() == normalized ||
        category.label.toLowerCase() == normalized) {
      return category.label;
    }
  }
  return null;
}

String defaultCategoryComparisonKey(String name) {
  final normalized = name.trim().toLowerCase();
  for (final category in defaultCategoryDefinitions) {
    if (category.name.toLowerCase() == normalized ||
        category.label.toLowerCase() == normalized) {
      return 'built-in:${category.key}';
    }
  }
  return normalized;
}

int defaultCategorySortOrder(String name) {
  final normalized = name.trim().toLowerCase();
  final index = defaultCategoryDefinitions.indexWhere(
    (category) =>
        category.name.toLowerCase() == normalized ||
        category.label.toLowerCase() == normalized,
  );
  return index < 0 ? defaultCategoryDefinitions.length : index;
}
