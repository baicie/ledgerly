import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/auto_ledger_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
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
}
