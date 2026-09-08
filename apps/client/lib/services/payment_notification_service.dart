import 'dart:convert';

import 'package:flutter/services.dart';

/// Abstraction over the platform side of the auto-ledger pipeline so that
/// tests can swap in a fake without going through the Android MethodChannel.
abstract class PaymentNotificationGateway {
  Future<bool> isAccessEnabled();
  Future<void> openAccessSettings();
  Future<List<PendingPaymentEvent>> getPendingEvents();
  Future<void> clearPendingEvents();
  Future<List<UnparsedPaymentEvent>> getUnparsedEvents();
  Future<void> clearUnparsedEvents();

  /// Removes a single unparsed event by id without touching its
  /// siblings. Returns `true` when the underlying queue still had the
  /// event (and therefore dropped it), `false` when nothing matched.
  Future<bool> dismissUnparsedEvent(String id);
}

/// Default [PaymentNotificationGateway] backed by the Android MethodChannel
/// defined in `MainActivity.kt`.
class PaymentNotificationService implements PaymentNotificationGateway {
  PaymentNotificationService();

  static const MethodChannel _channel = MethodChannel(
    'app.ledgerly.ledgerly_client/payment',
  );

  @override
  Future<bool> isAccessEnabled() async {
    final result =
        await _channel.invokeMethod<bool>('isNotificationAccessEnabled');
    return result ?? false;
  }

  @override
  Future<void> openAccessSettings() async {
    await _channel.invokeMethod<void>('openNotificationSettings');
  }

  @override
  Future<List<PendingPaymentEvent>> getPendingEvents() async {
    final raw = await _channel.invokeMethod<String>('getPendingPaymentEvents');
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (item) => PendingPaymentEvent.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  @override
  Future<void> clearPendingEvents() async {
    await _channel.invokeMethod<void>('clearPendingPaymentEvents');
  }

  @override
  Future<List<UnparsedPaymentEvent>> getUnparsedEvents() async {
    final raw =
        await _channel.invokeMethod<String>('getUnparsedPaymentEvents');
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (item) => UnparsedPaymentEvent.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  @override
  Future<void> clearUnparsedEvents() async {
    await _channel.invokeMethod<void>('clearUnparsedPaymentEvents');
  }

  @override
  Future<bool> dismissUnparsedEvent(String id) async {
    final result = await _channel.invokeMethod<bool>(
      'dismissUnparsedPaymentEvent',
      <String, dynamic>{'id': id},
    );
    return result ?? false;
  }
}

class PendingPaymentEvent {
  const PendingPaymentEvent({
    required this.id,
    required this.platform,
    required this.direction,
    required this.amountMinor,
    required this.rawText,
    required this.timestamp,
    this.merchant,
  });

  final String id;
  final String platform;
  final String direction;
  final int amountMinor;
  final String? merchant;
  final String rawText;
  final int timestamp;

  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(timestamp);

  factory PendingPaymentEvent.fromJson(Map<String, dynamic> json) {
    return PendingPaymentEvent(
      id: json['id'] as String,
      platform: json['platform'] as String,
      direction: (json['direction'] as String?) ?? 'expense',
      amountMinor: (json['amountMinor'] as num).toInt(),
      merchant: json['merchant'] as String?,
      rawText: json['rawText'] as String? ?? '',
      timestamp: (json['timestamp'] as num).toInt(),
    );
  }
}

/// A notification that the parser could not classify.
///
/// These are kept on-device (SharedPreferences) by the Kotlin listener so
/// the user can see what was missed and decide whether to ignore the
/// payload, file an upstream bug, or extend the parser.
class UnparsedPaymentEvent {
  const UnparsedPaymentEvent({
    required this.id,
    required this.packageName,
    required this.platform,
    required this.reasonTag,
    required this.rawText,
    required this.timestamp,
  });

  final String id;
  final String packageName;
  /// May be `null` when the parser rejected the notification before it
  /// could recognise the platform (e.g. blank content).
  final String? platform;
  /// Stable tag from [PaymentParser] identifying the failure mode.
  /// See the `reasonTag` doc on each [PaymentParseResult] subclass.
  final String reasonTag;
  final String rawText;
  final int timestamp;

  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(timestamp);

  factory UnparsedPaymentEvent.fromJson(Map<String, dynamic> json) {
    return UnparsedPaymentEvent(
      id: json['id'] as String,
      packageName: json['packageName'] as String? ?? '',
      platform: json['platform'] as String?,
      reasonTag: json['reasonTag'] as String? ?? 'unknown',
      rawText: json['rawText'] as String? ?? '',
      timestamp: (json['timestamp'] as num).toInt(),
    );
  }
}