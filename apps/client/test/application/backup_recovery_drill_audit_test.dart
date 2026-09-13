import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_recovery_drill_audit.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores newest recovery drills first and bounds history', () async {
    final store = BackupRecoveryDrillAuditStore();
    for (var minute = 0; minute < 25; minute++) {
      await store.recordSuccess(
        at: DateTime.utc(2026, 1, 1).add(Duration(minutes: minute)),
        encrypted: minute.isEven,
        incremental: minute.isOdd,
        bookCount: minute,
        transactionCount: minute + 1,
        attachmentCount: minute + 2,
      );
    }

    final audits = await store.read();

    expect(audits, hasLength(BackupRecoveryDrillAuditStore.targetSize));
    expect(audits.first.at, DateTime.utc(2026, 1, 1, 0, 24));
    expect(audits.first.bookCount, 24);
    expect(audits.last.at, DateTime.utc(2026, 1, 1, 0, 5));
  });

  test('records failures, handles malformed data, and clears history',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackupRecoveryDrillAuditStore.preferencesKey,
      '{"invalid":true}',
    );
    final store = BackupRecoveryDrillAuditStore();

    expect(await store.read(), isEmpty);

    await store.recordFailure(at: DateTime.utc(2026, 2, 1));
    final audits = await store.read();
    expect(audits, hasLength(1));
    expect(audits.single.status, BackupRecoveryDrillAuditStatus.failed);

    await store.clear();
    expect(await store.read(), isEmpty);
  });
}
