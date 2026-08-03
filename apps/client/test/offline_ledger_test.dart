import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';

void main() {
  test('offline create expense updates balance projection', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final repo = LedgerRepository(db);
    await repo.seedIfEmpty();
    final service = LedgerAppService(repo);

    await service.createExpense(
      expenseAccountId: 'acc_food',
      fundingAccountId: 'acc_cash',
      amountMinor: BigInt.from(3000),
      description: 'Lunch',
    );

    final summaries = await repo.watchSummariesSync('book_default');
    expect(summaries, hasLength(1));
    expect(summaries.first.description, 'Lunch');

    expect(await repo.accountBalance('acc_food'), BigInt.from(3000));
    expect(await repo.accountBalance('acc_cash'), BigInt.from(-3000));
  });
}
