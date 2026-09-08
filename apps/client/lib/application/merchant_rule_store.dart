import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'merchant_classifier.dart';

/// Persistent store for user-defined merchant classification rules.
///
/// The auto-ledger pipeline ships with a built-in default rule set
/// ([MerchantClassifier.defaultMerchantRules]); this store layers user
/// overrides on top of those defaults. User rules win first-match so that
/// users can fix incorrect categorizations without waiting for upstream
/// fixes.
///
/// Rules are persisted as JSON in SharedPreferences. The schema is
/// intentionally narrow: `{ id, categoryKey, needles[] }`. New fields
/// should be optional so older payloads keep loading.
class MerchantRuleStore {
  MerchantRuleStore({
    @visibleForTesting SharedPreferences? prefs,
    @visibleForTesting String preferencesKey = defaultPreferencesKey,
  }) : _prefs = prefs,
       _preferencesKey = preferencesKey;

  static const String defaultPreferencesKey = 'ledgerly.auto_ledger.rules';

  /// Identifier used to scope the SharedPreferences key. Tests can
  /// override this to keep fixtures isolated.
  final String _preferencesKey;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _preferences() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Load every persisted user rule, returning an empty list when nothing
  /// is stored or when the payload is unreadable. Errors are intentionally
  /// swallowed so that a corrupted entry cannot block the auto-ledger
  /// pipeline from starting.
  Future<List<MerchantRule>> load() async {
    final prefs = await _preferences();
    final raw = prefs.getString(_preferencesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => _ruleFromJson(Map<String, dynamic>.from(item)))
          .whereType<MerchantRule>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Replace the persisted rule list atomically.
  Future<void> save(List<MerchantRule> rules) async {
    final prefs = await _preferences();
    final encoded = jsonEncode(
      rules.map((rule) => _ruleToJson(rule)).toList(),
    );
    await prefs.setString(_preferencesKey, encoded);
  }

  /// Add a single rule and persist. Returns the resulting full list so
  /// callers can rebuild their classifier without re-querying storage.
  Future<List<MerchantRule>> add(MerchantRule rule) async {
    final existing = await load();
    final next = [...existing, rule];
    await save(next);
    return next;
  }

  /// Remove the rule whose id matches [ruleId]. Returns the resulting
  /// full list (without the removed rule) so the caller can rebuild.
  Future<List<MerchantRule>> remove(String ruleId) async {
    final existing = await load();
    final next = existing.where((rule) => rule.id != ruleId).toList();
    if (next.length == existing.length) return existing;
    await save(next);
    return next;
  }

  /// Reset all user rules. Returns an empty list. Useful for the
  /// "Restore defaults" entry in the settings page.
  Future<List<MerchantRule>> clear() async {
    final prefs = await _preferences();
    await prefs.remove(_preferencesKey);
    return const [];
  }

  Map<String, dynamic> _ruleToJson(MerchantRule rule) {
    return {
      'id': rule.id,
      'categoryKey': rule.categoryKey,
      'needles': rule.needles,
    };
  }

  MerchantRule? _ruleFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final categoryKey = json['categoryKey'];
    final needles = json['needles'];
    if (id is! String ||
        categoryKey is! String ||
        needles is! List ||
        needles.isEmpty) {
      return null;
    }
    final cleanNeedles = needles
        .whereType<String>()
        .map((needle) => needle.trim())
        .where((needle) => needle.isNotEmpty)
        .toList();
    if (cleanNeedles.isEmpty) return null;
    return MerchantRule(
      id: id,
      categoryKey: categoryKey,
      needles: cleanNeedles,
    );
  }
}
