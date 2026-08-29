import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/config/api_endpoint_messages.dart';
import 'package:ledgerly_client/l10n/l10n.dart';

void main() {
  tearDown(() {
    L10n.locale = const Locale('zh');
  });

  test('falls back to Chinese and translates English', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));

    expect(zh.navFeed, '流水');
    expect(en.navFeed, 'Feed');
    expect(zh.newBook, '新建账本');
    expect(en.newBook, 'New book');
    expect(localizedLedgerName(zh, 'Personal'), '标准账本');
    expect(localizedLedgerName(en, 'Personal'), 'Standard book');
    expect(zh.monthlyInsightEntryTitle, '每月分析');
    expect(en.monthlyInsightEntryTitle, 'Monthly insight');
    expect(
      L10n.resolve(const Locale('fr'), AppLocalizations.supportedLocales),
      const Locale('zh'),
    );
    expect(
      L10n.resolve(const Locale('en', 'US'), AppLocalizations.supportedLocales),
      const Locale('en'),
    );
  });

  test('endpoint errors follow the passed localizations', () {
    L10n.locale = const Locale('en');
    final error = FormatException('Release builds require HTTPS');
    expect(
      apiEndpointErrorText(error),
      lookupAppLocalizations(const Locale('en')).requireHttpsLanOk,
    );
    expect(
      apiEndpointErrorText(error, lookupAppLocalizations(const Locale('zh'))),
      '请使用 HTTPS；原生客户端也支持局域网 IP 地址',
    );
  });
}
