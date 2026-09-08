import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/merchant_classifier.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Reset the in-memory SharedPreferences backend so each test gets a
    // clean slate. The store uses the platform-default key, which is
    // shared across the entire test process otherwise.
    SharedPreferences.setMockInitialValues({});
  });

  group('MerchantRuleStore', () {
    test('load returns empty list when nothing has been persisted', () async {
      final store = MerchantRuleStore();
      expect(await store.load(), isEmpty);
    });

    test('save + load round-trips user rules', () async {
      final store = MerchantRuleStore();
      const ruleA = MerchantRule(
        id: 'a',
        categoryKey: 'acc_food',
        needles: ['咖啡'],
      );
      const ruleB = MerchantRule(
        id: 'b',
        categoryKey: 'acc_shopping',
        needles: ['便利店'],
      );
      await store.save([ruleA, ruleB]);
      final reloaded = await store.load();
      expect(reloaded, equals([ruleA, ruleB]));
    });

    test('add appends and persists', () async {
      final store = MerchantRuleStore();
      const ruleA = MerchantRule(
        id: 'a',
        categoryKey: 'acc_food',
        needles: ['咖啡'],
      );
      const ruleB = MerchantRule(
        id: 'b',
        categoryKey: 'acc_shopping',
        needles: ['便利店'],
      );
      await store.add(ruleA);
      await store.add(ruleB);
      expect(await store.load(), equals([ruleA, ruleB]));
    });

    test('remove drops the matching id and persists', () async {
      final store = MerchantRuleStore();
      const ruleA = MerchantRule(
        id: 'a',
        categoryKey: 'acc_food',
        needles: ['咖啡'],
      );
      const ruleB = MerchantRule(
        id: 'b',
        categoryKey: 'acc_shopping',
        needles: ['便利店'],
      );
      await store.save([ruleA, ruleB]);

      final after = await store.remove('a');
      expect(after, equals([ruleB]));

      // Removing an unknown id is a no-op and returns the existing list.
      final unchanged = await store.remove('does-not-exist');
      expect(unchanged, equals([ruleB]));
    });

    test('clear empties persisted rules', () async {
      final store = MerchantRuleStore();
      await store.save([
        const MerchantRule(id: 'a', categoryKey: 'acc_food', needles: ['咖啡']),
      ]);
      expect(await store.clear(), isEmpty);
      expect(await store.load(), isEmpty);
    });

    test('trims and drops empty needles when persisting', () async {
      final store = MerchantRuleStore();
      // We can't construct a MerchantRule with an empty needles list
      // through the public API (constructor is permissive), so we test
      // the loader's tolerance of junk instead.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        MerchantRuleStore.defaultPreferencesKey,
        '[{"id":"a","categoryKey":"acc_food","needles":[" 咖啡 ",""]}]',
      );
      final reloaded = await store.load();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.needles, equals(['咖啡']));
    });

    test('load returns empty list when payload is corrupted JSON', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        MerchantRuleStore.defaultPreferencesKey,
        'not a json array',
      );
      final store = MerchantRuleStore();
      expect(await store.load(), isEmpty);
    });

    test('load ignores entries with missing fields', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        MerchantRuleStore.defaultPreferencesKey,
        '['
        '{"id":"a","categoryKey":"acc_food","needles":["咖啡"]},'
        '{"categoryKey":"acc_food","needles":["咖啡"]},' // missing id
        '{"id":"b","needles":["咖啡"]},' // missing categoryKey
        '{"id":"c","categoryKey":"acc_food","needles":[]},' // empty needles
        '{"id":"d","categoryKey":"acc_food","needles":["  "]}' // whitespace only
        ']',
      );
      final store = MerchantRuleStore();
      final reloaded = await store.load();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.id, 'a');
    });
  });

  group('MerchantClassifier merged rules', () {
    test('user rule wins over built-in defaults when listed first', () {
      const customClassifier = MerchantClassifier(
        rules: [
          // User overrides "美团" to a non-default category.
          MerchantRule(
            id: 'override-meituan',
            categoryKey: 'acc_shopping',
            needles: ['美团'],
          ),
          ...defaultMerchantRules,
        ],
      );
      // Without the override this would map to acc_food.
      expect(
        customClassifier.classify(merchant: '美团外卖', direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_shopping')),
      );
    });

    test('built-in defaults still match when no user rule fires', () {
      const customClassifier = MerchantClassifier(
        rules: [
          MerchantRule(
            id: 'override-coffee',
            categoryKey: 'acc_shopping',
            needles: ['美团'],
          ),
          ...defaultMerchantRules,
        ],
      );
      // 麦当劳 not in any user rule, falls through to default (acc_food).
      expect(
        customClassifier.classify(merchant: '麦当劳', direction: 'expense'),
        equals(accountId(defaultBookId, 'acc_food')),
      );
    });
  });
}
