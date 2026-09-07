import '../domain/ids.dart';

/// Pure, side-effect-free merchant classifier used by [AutoLedgerService].
///
/// Keeping this in its own file makes it easy to unit test and to extend
/// with user-defined rules later without touching the sync service.
class MerchantClassifier {
  const MerchantClassifier({this.rules = defaultMerchantRules});

  /// Ordered list of classification rules. First match wins.
  final List<MerchantRule> rules;

  /// Map a free-form merchant string to a default category account id.
  ///
  /// Returns the fallback `acc_other_expense` / `acc_other_income` account
  /// (which always exists thanks to seedIfEmpty()) when no rule matches.
  String classify({
    required String? merchant,
    required String direction,
    String bookId = defaultBookId,
  }) {
    final fallback = direction == 'income'
        ? accountId(bookId, 'acc_other_income')
        : accountId(bookId, 'acc_other_expense');
    if (merchant == null || merchant.trim().isEmpty) return fallback;

    final key = merchant.toLowerCase();
    for (final rule in rules) {
      for (final needle in rule.needles) {
        if (key.contains(needle.toLowerCase())) {
          return accountId(bookId, rule.categoryKey);
        }
      }
    }
    return fallback;
  }
}

class MerchantRule {
  const MerchantRule({
    required this.categoryKey,
    required this.needles,
  });

  /// Default category key under `defaultBookId` (e.g. `acc_food`).
  final String categoryKey;

  /// Substrings that, when found inside the merchant string, map to
  /// [categoryKey]. Matching is case-insensitive.
  final List<String> needles;
}

/// Built-in merchant -> category rules. Order matters: first match wins.
const defaultMerchantRules = <MerchantRule>[
  MerchantRule(
    categoryKey: 'acc_food',
    needles: ['美团', '饿了么', '麦当劳', '肯德基', '星巴克', '瑞幸', '海底捞'],
  ),
  MerchantRule(
    categoryKey: 'acc_transport_taxi',
    needles: ['滴滴', '高德打车', '曹操出行', 'T3出行', '首汽约车'],
  ),
  MerchantRule(
    categoryKey: 'acc_transport_public',
    needles: ['地铁', '公交', '12306', '铁路', '一卡通', '市民卡'],
  ),
  MerchantRule(
    categoryKey: 'acc_transport_car',
    needles: ['加油', '中石化', '中石油', '壳牌', '停车'],
  ),
  MerchantRule(
    categoryKey: 'acc_shopping',
    needles: ['淘宝', '天猫', '京东', '拼多多', '唯品会'],
  ),
  MerchantRule(
    categoryKey: 'acc_shopping_daily',
    needles: ['盒马', '永辉', '沃尔玛', '家乐福', '便利店', '711', '罗森'],
  ),
  MerchantRule(
    categoryKey: 'acc_housing_utilities',
    needles: ['电费', '水费', '燃气', '国家电网', '中国移动', '中国联通', '中国电信'],
  ),
  MerchantRule(
    categoryKey: 'acc_housing_rent',
    needles: ['房租', '自如', '链家', '我爱我家'],
  ),
  MerchantRule(
    categoryKey: 'acc_leisure_entertainment',
    needles: [
      '猫眼', '淘票票', '大麦', '网易云', 'QQ音乐',
      '腾讯视频', '爱奇艺', '优酷', 'B站', '哔哩哔哩',
    ],
  ),
  MerchantRule(
    categoryKey: 'acc_leisure_travel',
    needles: ['携程', '飞猪', '去哪儿', '航旅纵横'],
  ),
  MerchantRule(
    categoryKey: 'acc_healthcare',
    needles: ['医院', '药房', '药店', '微医', '好大夫'],
  ),
  MerchantRule(
    categoryKey: 'acc_education',
    needles: ['学而思', '猿辅导', '作业帮', '得到', '极客时间'],
  ),
];
