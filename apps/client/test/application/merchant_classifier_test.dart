import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/merchant_classifier.dart';
import 'package:ledgerly_client/domain/ids.dart';

void main() {
  const classifier = MerchantClassifier();

  group('MerchantClassifier', () {
    test('returns other_expense for unknown merchant', () {
      expect(
        classifier.classify(merchant: '宇宙杂货铺', direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_other_expense')),
      );
    });

    test('returns other_income for unknown merchant with income direction', () {
      expect(
        classifier.classify(merchant: '神秘打款', direction: 'income'),
        equals(accountId(defaultBookId, 'acc_other_income')),
      );
    });

    test('falls back when merchant is null or blank', () {
      expect(
        classifier.classify(merchant: null, direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_other_expense')),
      );
      expect(
        classifier.classify(merchant: '   ', direction: 'income'),
        equals(accountId(defaultBookId, 'acc_other_income')),
      );
    });

    test('maps food merchants to acc_food', () {
      const merchants = ['美团外卖', '饿了么星选', '麦当劳麦乐送', '肯德基宅急送',
          '星巴克咖啡', '瑞幸咖啡', '海底捞火锅'];
      for (final m in merchants) {
        expect(
          classifier.classify(merchant: m, direction: 'expense'),
          equals(accountId(defaultBookId, 'acc_food')),
          reason: '$m should map to acc_food',
        );
      }
    });

    test('maps taxi merchants to acc_transport_taxi', () {
      const merchants = ['滴滴出行', '高德打车', '曹操出行', 'T3出行', '首汽约车'];
      for (final m in merchants) {
        expect(
          classifier.classify(merchant: m, direction: 'expense'),
          equals(accountId(defaultBookId, 'acc_transport_taxi')),
          reason: '$m should map to acc_transport_taxi',
        );
      }
    });

    test('maps 12306 to public transport, not taxi', () {
      // Taxi rules come first, so make sure 12306 doesn't accidentally
      // match a taxi substring. Since 12306 is a standalone token in
      // 12306 order, the rule ordering keeps it on public transport.
      expect(
        classifier.classify(merchant: '12306火车票', direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_transport_public')),
      );
    });

    test('maps shopping merchants to acc_shopping', () {
      const merchants = ['淘宝', '天猫旗舰店', '京东自营', '拼多多', '唯品会'];
      for (final m in merchants) {
        expect(
          classifier.classify(merchant: m, direction: 'expense'),
          equals(accountId(defaultBookId, 'acc_shopping')),
          reason: '$m should map to acc_shopping',
        );
      }
    });

    test('maps box-horse / convenience stores to daily shopping, not shopping',
        () {
      // The default rules order acc_shopping before acc_shopping_daily, but
      // 盒马 doesn't appear in the shopping needle list, so it falls through
      // to daily. Same for 711 / 罗森 / 永辉 / 沃尔玛.
      const merchants = ['盒马鲜生', '711便利店', '罗森', '永辉超市', '沃尔玛'];
      for (final m in merchants) {
        expect(
          classifier.classify(merchant: m, direction: 'expense'),
          equals(accountId(defaultBookId, 'acc_shopping_daily')),
          reason: '$m should map to acc_shopping_daily',
        );
      }
    });

    test('matches are case-insensitive (English merchants)', () {
      const classifierWithEnglishRule = MerchantClassifier(
        rules: [
          MerchantRule(categoryKey: 'acc_shopping', needles: ['amazon', 'AMZN']),
          ...defaultMerchantRules,
        ],
      );
      expect(
        classifierWithEnglishRule.classify(
          merchant: 'AMAZON.COM',
          direction: 'expense',
        ),
        equals(accountId(defaultBookId, 'acc_shopping')),
      );
    });

    test('honours custom rules and falls back when none match', () {
      const custom = MerchantClassifier(
        rules: [
          MerchantRule(
            categoryKey: 'acc_housing_rent',
            needles: ['landlord'],
          ),
        ],
      );
      expect(
        custom.classify(merchant: 'My Landlord', direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_housing_rent')),
      );
      expect(
        custom.classify(merchant: 'Random Coffee Shop', direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_other_expense')),
      );
    });

    test('respects the supplied bookId', () {
      const customBook = 'book_other';
      expect(
        classifier.classify(
          merchant: '美团外卖',
          direction: 'expense',
          bookId: customBook,
        ),
        equals('$customBook:acc_food'),
      );
    });

    test('first matching rule wins even if the merchant has multiple keywords',
        () {
      // 滴滴 ridesharing inside a 淘宝 order (rare but legal) still maps
      // to transport_taxi because that rule precedes shopping in the list.
      expect(
        classifier.classify(
          merchant: '滴滴出行-淘宝联名卡',
          direction: 'expense',
        ),
        equals(accountId(defaultBookId, 'acc_transport_taxi')),
      );
    });
  });
}
