import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/services/payment_notification_service.dart';

void main() {
  group('PendingPaymentEvent.fromJson', () {
    test('parses all fields when present', () {
      final event = PendingPaymentEvent.fromJson({
        'id': 'wechat-1788705000000-2850',
        'platform': 'wechat',
        'direction': 'expense',
        'amountMinor': 2850,
        'merchant': '美团外卖',
        'rawText': '微信支付：向美团外卖付款28.50元',
        'timestamp': 1788705000000,
      });
      expect(event.id, 'wechat-1788705000000-2850');
      expect(event.platform, 'wechat');
      expect(event.direction, 'expense');
      expect(event.amountMinor, 2850);
      expect(event.merchant, '美团外卖');
      expect(event.rawText, contains('美团'));
      expect(
        event.occurredAt,
        equals(DateTime.fromMillisecondsSinceEpoch(1788705000000)),
      );
    });

    test('defaults direction to expense when missing', () {
      final event = PendingPaymentEvent.fromJson({
        'id': 'alipay-1',
        'platform': 'alipay',
        'amountMinor': 100,
        'rawText': '',
        'timestamp': 1,
      });
      expect(event.direction, 'expense');
    });

    test('allows null merchant', () {
      final event = PendingPaymentEvent.fromJson({
        'id': 'alipay-1',
        'platform': 'alipay',
        'direction': 'income',
        'amountMinor': 100,
        'rawText': '',
        'timestamp': 1,
      });
      expect(event.merchant, isNull);
    });

    test('treats missing rawText as empty string', () {
      final event = PendingPaymentEvent.fromJson({
        'id': 'alipay-1',
        'platform': 'alipay',
        'direction': 'expense',
        'amountMinor': 100,
        'timestamp': 1,
      });
      expect(event.rawText, '');
    });
  });
}
