import 'package:ledger_sync/ledger_sync.dart';
import 'package:test/test.dart';

PendingMutation expenseMutation(String id, String mutationId) {
  return PendingMutation(
    mutationId: mutationId,
    entityType: 'transaction',
    entityId: id,
    operation: 'create',
    baseVersion: 0,
    payload: {
      'description': 'Lunch',
      'entries': [
        {'accountId': 'acc_food', 'amountMinor': '2500', 'currency': 'CNY'},
        {'accountId': 'acc_cash', 'amountMinor': '-2500', 'currency': 'CNY'},
      ],
    },
  );
}

void main() {
  test('two devices converge via push/pull', () {
    final server = InMemorySyncServer();
    final a = DeviceLedger(deviceId: 'dev_a');
    final b = DeviceLedger(deviceId: 'dev_b');
    const book = 'book_1';

    a.enqueue(expenseMutation('tx_1', 'mut_a1'));
    a.push(server, book);
    // Response loss simulation: push again same mutation
    a.pending.add(expenseMutation('tx_1', 'mut_a1'));
    a.push(server, book);

    b.pull(server, book);
    expect(b.entities.containsKey('tx_1'), isTrue);
    expect(b.entities['tx_1']!['version'], 1);

    b.enqueue(expenseMutation('tx_2', 'mut_b1'));
    b.push(server, book);
    a.pull(server, book);
    expect(a.entities.containsKey('tx_2'), isTrue);
  });

  test('unbalanced mutation rejected without blocking later ones', () {
    final server = InMemorySyncServer();
    final a = DeviceLedger(deviceId: 'dev_a');
    const book = 'book_1';
    a.pending.add(
      PendingMutation(
        mutationId: 'bad',
        entityType: 'transaction',
        entityId: 'tx_bad',
        operation: 'create',
        baseVersion: 0,
        payload: {
          'entries': [
            {'accountId': 'acc_food', 'amountMinor': '100', 'currency': 'CNY'},
            {'accountId': 'acc_cash', 'amountMinor': '-50', 'currency': 'CNY'},
          ],
        },
      ),
    );
    a.pending.add(expenseMutation('tx_ok', 'ok'));
    final receipts = server.push(
      bookId: book,
      deviceId: a.deviceId,
      mutations: a.pending,
    );
    expect(receipts[0].resultCode, 'LEDGER_UNBALANCED');
    expect(receipts[1].status, 'applied');
  });
}
