import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/auto_ledger_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/merchant_classifier.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/services/payment_notification_service.dart';

class _FakeNotifications implements PaymentNotificationGateway {
  _FakeNotifications(this._events);

  final List<PendingPaymentEvent> _events;
  int clearCount = 0;
  final List<List<PendingPaymentEvent>> snapshots = [];

  @override
  Future<bool> isAccessEnabled() async => true;

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<List<PendingPaymentEvent>> getPendingEvents() async {
    // Hand out a defensive copy so callers cannot mutate the queue.
    final copy = List<PendingPaymentEvent>.of(_events);
    snapshots.add(copy);
    return copy;
  }

  @override
  Future<void> clearPendingEvents() async {
    clearCount += 1;
  }

  @override
  Future<List<UnparsedPaymentEvent>> getUnparsedEvents() async {
    return const [];
  }

  @override
  Future<void> clearUnparsedEvents() async {}

  @override
  Future<bool> dismissUnparsedEvent(String id) async => false;
}

Future<({LedgerRepository repo, LedgerAppService ledger, AppDatabase db})>
    _bootstrap() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = LedgerRepository(
    db,
    deviceIdLoader: () async => 'auto-ledger-test-device',
  );
  await repo.seedIfEmpty();
  final ledger = LedgerAppService(repo);
  return (repo: repo, ledger: ledger, db: db);
}

void main() {
  // Each test creates its own in-memory database to avoid drift complaining
  // about multiple AppDatabase instances sharing one QueryExecutor.
  tearDown(() async {});

  test('describe attaches the platform label and merchant', () {
    expect(
      AutoLedgerService.describe(
        const PendingPaymentEvent(
          id: 'id',
          platform: 'wechat',
          direction: 'expense',
          amountMinor: 100,
          rawText: '',
          timestamp: 0,
          merchant: '美团外卖',
        ),
        '美团外卖',
      ),
      '微信支付 · 美团外卖',
    );
    expect(
      AutoLedgerService.describe(
        const PendingPaymentEvent(
          id: 'id',
          platform: 'alipay',
          direction: 'income',
          amountMinor: 100,
          rawText: '',
          timestamp: 0,
        ),
        null,
      ),
      '支付宝 · 未知商户',
    );
  });

  test('empty queue short-circuits without touching the database', () async {
    final localDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(localDb.close);
    final fake = _FakeNotifications(const []);
    final service = AutoLedgerService(
      repository: LedgerRepository(
        localDb,
        deviceIdLoader: () async => 'device',
      ),
      ledger: LedgerAppService(
        LedgerRepository(localDb, deviceIdLoader: () async => 'device'),
      ),
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report, const AutoLedgerSyncReport(posted: 0, duplicates: 0, skipped: 0));
    // An empty queue short-circuits before calling clearPendingEvents, so
    // we leave the native queue untouched.
    expect(fake.clearCount, 0);
  });

  test('posts expense event and classifies to the correct category',
      () async {
    final boot = await _bootstrap();
    final event = PendingPaymentEvent(
      id: 'wechat-1-2850',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 2850,
      merchant: '美团外卖',
      rawText: '微信支付：向美团外卖付款28.50元',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final fake = _FakeNotifications([event]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 1);
    expect(report.duplicates, 0);
    expect(report.skipped, 0);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(1));
    final tx = txs.single;
    expect(tx.kind, TransactionSummaryKind.expense);
    expect(tx.amountMinor, BigInt.from(2850));
    expect(tx.categoryName, 'Food');
    expect(tx.description, contains('微信支付'));
    expect(tx.description, contains('美团外卖'));
  });

  test('posted transactions carry the auto_ledger source tag', () async {
    final boot = await _bootstrap();
    final events = [
      PendingPaymentEvent(
        id: 'wechat-source-1',
        platform: 'wechat',
        direction: 'expense',
        amountMinor: 1850,
        merchant: '美团外卖',
        rawText: '微信支付：向美团外卖付款18.50元',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
      PendingPaymentEvent(
        id: 'alipay-source-2',
        platform: 'alipay',
        direction: 'income',
        amountMinor: 10000,
        merchant: '房东',
        rawText: '支付宝：收到 房东 转账100.00元',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    final fake = _FakeNotifications(events);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 2);

    final rows = await boot.db
        .select(boot.db.transactions)
        .get();
    expect(rows, hasLength(2));
    expect(
      rows.map((r) => r.source).toSet(),
      equals({autoLedgerSource}),
      reason: 'all auto-ledger rows should carry the auto_ledger source',
    );

    // Mutation payload also carries the source tag so the server receives it
    // during sync push.
    final mutations = await boot.db.select(boot.db.pendingMutations).get();
    expect(mutations, hasLength(2));
    for (final mutation in mutations) {
      final payload = jsonDecode(mutation.payloadJson) as Map<String, dynamic>;
      expect(payload['source'], autoLedgerSource);
    }
  });

  test('deduplicates a repeat event inside the time window', () async {
    final boot = await _bootstrap();
    final now = DateTime.now();
    final firstEvent = PendingPaymentEvent(
      id: 'wechat-1-3200',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 3200,
      merchant: '美团外卖',
      rawText: '微信支付：向美团外卖付款32元',
      timestamp: now.millisecondsSinceEpoch,
    );
    final duplicateEvent = PendingPaymentEvent(
      id: 'wechat-2-3200',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 3200,
      merchant: '美团外卖',
      rawText: '微信支付：支付 ¥32.00',
      // 5 seconds later, well inside the 60s dedup window.
      timestamp: now.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
    );

    final fake = _FakeNotifications([firstEvent, duplicateEvent]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 1);
    expect(report.duplicates, 1);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(1));
  });

  test('does not deduplicate events that are clearly distinct in amount',
      () async {
    final boot = await _bootstrap();
    final now = DateTime.now();
    final e1 = PendingPaymentEvent(
      id: 'wechat-1',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 1000,
      merchant: '美团外卖',
      rawText: '',
      timestamp: now.millisecondsSinceEpoch,
    );
    final e2 = PendingPaymentEvent(
      id: 'wechat-2',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 1200,
      merchant: '美团外卖',
      rawText: '',
      timestamp: now.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
    );

    final fake = _FakeNotifications([e1, e2]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 2);
    expect(report.duplicates, 0);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(2));
  });

  test('skips events older than the staleness cutoff', () async {
    final boot = await _bootstrap();
    final now = DateTime.now();
    final stale = PendingPaymentEvent(
      id: 'wechat-stale',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 100,
      merchant: '美团外卖',
      rawText: '',
      timestamp: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    );

    final fake = _FakeNotifications([stale]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 0);
    expect(report.skipped, 1);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, isEmpty);
  });

  test('classifies income events through the income account fallback',
      () async {
    final boot = await _bootstrap();
    final event = PendingPaymentEvent(
      id: 'alipay-income-1',
      platform: 'alipay',
      direction: 'income',
      amountMinor: 10000,
      merchant: '神秘人',
      rawText: '支付宝收款 100 元',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final fake = _FakeNotifications([event]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 1);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(1));
    expect(txs.single.kind, TransactionSummaryKind.income);
  });

  test(
      'uses a stable mutation id derived from the client event id so server '
      'deduplication survives retries', () async {
    final boot = await _bootstrap();
    final now = DateTime.now();
    final event = PendingPaymentEvent(
      id: 'wechat-stable-1',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 2850,
      merchant: '美团外卖',
      rawText: '微信支付 28.50 元',
      timestamp: now.millisecondsSinceEpoch,
    );

    // First sync posts the event.
    final firstService = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: _FakeNotifications([event]),
    );
    final firstReport = await firstService.syncPending();
    expect(firstReport.posted, 1);

    // Capture the mutation id that landed on the wire so we can compare it
    // against the second attempt.
    final firstMutation = (await boot.db
            .select(boot.db.pendingMutations)
            .get())
        .single;
    expect(
      firstMutation.mutationId,
      'auto:$defaultBookId:wechat-stable-1',
      reason: 'auto-ledger mutation ids should be namespaced with auto:',
    );

    // Simulate a crash / restart: rebuild the service from scratch, leave
    // the existing transaction in place, and re-sync the same event id.
    // The local SQLite dedup window already suppresses a second insertion,
    // but the durable mutation id must remain identical so the server can
    // collapse a re-pushed attempt.
    final rebootedLedger = LedgerAppService(boot.repo);
    final secondService = AutoLedgerService(
      repository: boot.repo,
      ledger: rebootedLedger,
      notifications: _FakeNotifications([event]),
    );
    final secondReport = await secondService.syncPending();
    // The ledger rejects the second insert because of the in-ledger dedup
    // window — that's the expected behaviour.
    expect(secondReport.posted, 0);
    expect(secondReport.duplicates, 1);

    // Still exactly one transaction and exactly one pending mutation,
    // and that mutation id matches the first sync's id.
    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(1));

    final mutations = await boot.db.select(boot.db.pendingMutations).get();
    expect(mutations, hasLength(1));
    expect(mutations.single.mutationId, firstMutation.mutationId);
  });

  test('posts two events that look similar but happen minutes apart',
      () async {
    final boot = await _bootstrap();
    final now = DateTime.now();
    final e1 = PendingPaymentEvent(
      id: 'wechat-1',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 3200,
      merchant: '美团外卖',
      rawText: '',
      timestamp: now.millisecondsSinceEpoch,
    );
    final e2 = PendingPaymentEvent(
      id: 'wechat-2',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 3200,
      merchant: '美团外卖',
      rawText: '',
      // 5 minutes later: outside the 60s dedup window, so both should post.
      timestamp: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );

    final fake = _FakeNotifications([e1, e2]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    final report = await service.syncPending();
    expect(report.posted, 2);
    expect(report.duplicates, 0);

    final txs = await boot.repo.watchSummariesSync(
      defaultBookId,
      monthStart: now.subtract(const Duration(days: 1)),
      monthEnd: now.add(const Duration(days: 1)),
    );
    expect(txs, hasLength(2));
  });

  group('computeFingerprint', () {
    test('same inputs produce the same fingerprint across calls', () {
      final occurredAt = DateTime.utc(2024, 4, 13, 12, 0, 0);
      final fp1 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: '美团外卖',
        bookId: defaultBookId,
      );
      final fp2 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: '美团外卖',
        bookId: defaultBookId,
      );
      expect(fp1, equals(fp2));
    });

    test('different amountMinor produces different fingerprint', () {
      final occurredAt = DateTime.utc(2024, 4, 13, 12, 0, 0);
      final fp1 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: '美团外卖',
        bookId: defaultBookId,
      );
      final fp2 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 3000,
        occurredAtUtc: occurredAt,
        merchant: '美团外卖',
        bookId: defaultBookId,
      );
      expect(fp1, isNot(equals(fp2)));
    });

    test('merchant case and whitespace are normalized', () {
      final occurredAt = DateTime.utc(2024, 4, 13, 12, 0, 0);
      final fp1 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: '美团外卖',
        bookId: defaultBookId,
      );
      final fp2 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: '  美团外卖  ',
        bookId: defaultBookId,
      );
      // Lower-case normalizes, leading/trailing spaces normalize.
      // These should be different because "美团外卖" vs "  美团外卖  " after trim are equal
      // but let me think again - after trim they are equal strings.
      // Actually "美团外卖" vs "  美团外卖  " → both trim to "美团外卖" so fp1 == fp2.
      expect(fp1, equals(fp2));
    });

    test('null merchant is treated as empty string', () {
      final occurredAt = DateTime.utc(2024, 4, 13, 12, 0, 0);
      final fp1 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: null,
        bookId: defaultBookId,
      );
      final fp2 = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: occurredAt,
        merchant: '',
        bookId: defaultBookId,
      );
      expect(fp1, equals(fp2));
    });

    test('fingerprint is a 64-character lowercase hex string (SHA-256)', () {
      final fp = AutoLedgerService.computeFingerprint(
        direction: 'expense',
        amountMinor: 2850,
        occurredAtUtc: DateTime.utc(2024, 4, 13, 12, 0, 0),
        merchant: '美团外卖',
        bookId: defaultBookId,
      );
      expect(fp.length, equals(64));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(fp), isTrue);
    });
  });

  test('posted auto-ledger transaction carries fingerprint in mutation payload',
      () async {
    final boot = await _bootstrap();
    final event = PendingPaymentEvent(
      id: 'wechat-fp-test',
      platform: 'wechat',
      direction: 'expense',
      amountMinor: 2850,
      merchant: '美团外卖',
      rawText: '微信支付：向美团外卖付款28.50元',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final fake = _FakeNotifications([event]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
    );

    await service.syncPending();

    final mutations = await boot.db.select(boot.db.pendingMutations).get();
    expect(mutations, hasLength(1));
    final payload =
        jsonDecode(mutations.single.payloadJson) as Map<String, dynamic>;
    expect(payload['sourceEventFingerprint'], isNotNull);
    expect(payload['sourceEventFingerprint'], hasLength(64));
  });

  test('user-defined merchant rules override the built-in defaults',
      () async {
    final boot = await _bootstrap();
    // Real life: the user wants "美团外卖" to count as shopping instead
    // of food. They create a user rule that wins before the built-in
    // food rules do.
    const userRules = [
      MerchantRule(
        id: 'meituan-is-shopping',
        categoryKey: 'acc_shopping',
        needles: ['美团'],
      ),
    ];
    final fake = _FakeNotifications([
      PendingPaymentEvent(
        id: 'wechat-user-rule-1',
        platform: 'wechat',
        direction: 'expense',
        amountMinor: 2850,
        merchant: '美团外卖',
        rawText: '微信支付：向美团外卖付款28.50元',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
      ruleLoader: () async => userRules,
    );

    final report = await service.syncPending();
    expect(report.posted, 1);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(1));
    // Without the user rule this would be 'Food'; the user rule pushes
    // it into shopping.
    expect(txs.single.categoryName, 'Shopping');
  });

  test(
      'falls back to defaults when the rule loader returns an empty list',
      () async {
    final boot = await _bootstrap();
    final fake = _FakeNotifications([
      PendingPaymentEvent(
        id: 'wechat-empty-rules-1',
        platform: 'wechat',
        direction: 'expense',
        amountMinor: 1850,
        merchant: '麦当劳麦乐送',
        rawText: '微信支付：麦当劳麦乐送18.50元',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    final service = AutoLedgerService(
      repository: boot.repo,
      ledger: boot.ledger,
      notifications: fake,
      // Empty list: should behave as if no user rules are configured.
      ruleLoader: () async => const [],
    );

    final report = await service.syncPending();
    expect(report.posted, 1);

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs.single.categoryName, 'Food');
  });

  test('rescueUnparsedEvent posts an expense with the rescue namespace',
      () async {
    final boot = await _bootstrap();
    final occurred = DateTime.utc(2026, 5, 1, 12, 0);
    await boot.ledger.rescueUnparsedEvent(
      direction: 'expense',
      amountMinor: BigInt.from(2380),
      merchant: '某小店',
      note: null,
      occurredAt: occurred,
      platform: 'wechat',
      reasonTag: 'no_amount',
      unparsedEventId: 'unparsed-test-001',
    );

    final txs = await boot.repo.watchSummariesSync(defaultBookId);
    expect(txs, hasLength(1));
    final tx = txs.single;
    expect(tx.amountMinor, BigInt.from(2380));
    expect(tx.kind, TransactionSummaryKind.expense);
    expect(tx.source, 'auto_ledger_rescue');
    expect(tx.description, contains('微信支付'));
    expect(tx.description, contains('某小店'));
  });

  test('rescueUnparsedEvent rejects a non-positive amount', () async {
    final boot = await _bootstrap();
    expect(
      () => boot.ledger.rescueUnparsedEvent(
        direction: 'expense',
        amountMinor: BigInt.zero,
        merchant: null,
        note: null,
        occurredAt: DateTime.utc(2026, 5, 1),
        platform: 'alipay',
        reasonTag: 'no_amount',
        unparsedEventId: 'unparsed-test-002',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'rescueUnparsedEvent derives a stable clientEventId so retries collapse',
    () async {
      final boot = await _bootstrap();
      final occurred = DateTime.utc(2026, 5, 1, 12, 0);
      await boot.ledger.rescueUnparsedEvent(
        direction: 'expense',
        amountMinor: BigInt.from(990),
        merchant: null,
        note: null,
        occurredAt: occurred,
        platform: 'wechat',
        reasonTag: 'no_amount',
        unparsedEventId: 'unparsed-test-003',
      );
      // Re-running with the same unparsed id should not double-post,
      // because the clientEventId is deterministic.
      await boot.ledger.rescueUnparsedEvent(
        direction: 'expense',
        amountMinor: BigInt.from(990),
        merchant: null,
        note: null,
        occurredAt: occurred,
        platform: 'wechat',
        reasonTag: 'no_amount',
        unparsedEventId: 'unparsed-test-003',
      );
      final txs = await boot.repo.watchSummariesSync(defaultBookId);
      expect(txs, hasLength(1));
    },
  );
}
