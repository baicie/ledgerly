import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_encryption.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_recovery_drill_audit.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('drills a plaintext incremental chain without changing metadata',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    await fixture.service.exportToFile();
    await _addExpense(fixture, description: 'drill transaction');
    await fixture.service.exportToFile(incremental: true);
    final before = await BackupMetadataStore().read();

    final result = await fixture.service.runRecoveryDrill();

    expect(result.encrypted, isFalse);
    expect(result.incremental, isTrue);
    expect(result.summary.transactions, 1);
    expect(result.bundledAttachmentCount, 0);
    final audits = await fixture.drillAudits.read();
    expect(audits, hasLength(1));
    expect(audits.single.status, BackupRecoveryDrillAuditStatus.success);
    expect(audits.single.incremental, isTrue);
    expect(audits.single.transactionCount, 1);
    final after = await BackupMetadataStore().read();
    expect(after.lastBackupPath, before.lastBackupPath);
    expect(after.baseBackupPath, before.baseBackupPath);
  });

  test('drills an encrypted backup only with the correct password', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await _addExpense(fixture, description: 'encrypted drill transaction');
    await fixture.service.exportToFile(password: 'password123');

    await expectLater(
      fixture.service.runRecoveryDrill(),
      throwsA(isA<BackupPasswordException>()),
    );
    await expectLater(
      fixture.service.runRecoveryDrill(password: 'wrong-password'),
      throwsA(isA<BackupPasswordException>()),
    );
    expect(
      (await fixture.drillAudits.read()).first.status,
      BackupRecoveryDrillAuditStatus.failed,
    );

    final result = await fixture.service.runRecoveryDrill(
      password: 'password123',
    );
    expect(result.backupId, isNotNull);
    expect(result.encrypted, isTrue);
    expect(result.incremental, isFalse);
    expect(result.summary.transactions, 1);
    final audits = await fixture.drillAudits.read();
    expect(audits, hasLength(3));
    expect(audits.first.status, BackupRecoveryDrillAuditStatus.success);
    expect(audits.first.encrypted, isTrue);
  });

  test('reports attachment integrity failures during a drill', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();

    final bytes = utf8.encode('attachment');
    final document = BackupDocument(
      summary: const BackupSummary(
        books: 0,
        accounts: 0,
        transactions: 0,
        transactionEntries: 0,
        recurringRules: 0,
        budgets: 0,
        attachments: 1,
        merchantRules: 0,
      ),
      payload: {
        'books': <Map<String, dynamic>>[],
        'accounts': <Map<String, dynamic>>[],
        'transactions': <Map<String, dynamic>>[],
        'transactionEntries': <Map<String, dynamic>>[],
        'recurringRules': <Map<String, dynamic>>[],
        'budgets': <Map<String, dynamic>>[],
        'attachments': [
          <String, dynamic>{'id': 'attachment-1'},
        ],
        'merchantRules': <Map<String, dynamic>>[],
      },
      attachmentIndex: [
        {
          'id': 'attachment-1',
          'size': bytes.length,
          'sha256': sha256.convert(utf8.encode('different')).toString(),
        },
      ],
      attachmentBinaries: [
        AttachmentBinary(
          id: 'attachment-1',
          bytes: Uint8List.fromList(bytes),
        ),
      ],
      backupId: 'drill-corrupt-attachment',
    );
    final path = await fixture.service.writeBackupToFile(document);
    await BackupMetadataStore().record(
      path: path,
      at: DateTime.now().toUtc(),
      backupId: document.backupId,
    );

    await expectLater(
      fixture.service.runRecoveryDrill(),
      throwsA(
        isA<BackupFormatException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
    expect(
      (await fixture.drillAudits.read()).first.status,
      BackupRecoveryDrillAuditStatus.failed,
    );
  });

  test('wipe clears persisted recovery drill audits', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.seed();
    await fixture.service.exportToFile();

    await fixture.service.runRecoveryDrill();
    expect(await fixture.drillAudits.read(), hasLength(1));

    await fixture.service.wipeLocalData();

    expect(await fixture.drillAudits.read(), isEmpty);
  });
}

Future<void> _addExpense(
  _Fixture fixture, {
  required String description,
}) {
  return LedgerAppService(fixture.repository).createExpense(
    expenseAccountId: accountKeyFood(defaultBookId),
    fundingAccountId: accountKeyCash(defaultBookId),
    amountMinor: BigInt.from(100),
    description: description,
  );
}

class _Fixture {
  _Fixture() : db = AppDatabase.forTesting(NativeDatabase.memory()) {
    repository = LedgerRepository(
      db,
      deviceIdLoader: () async => 'recovery-drill-test-device',
    );
    filePort = InMemoryBackupFilePort();
    drillAudits = BackupRecoveryDrillAuditStore();
    service = BackupService(
      database: db,
      recurring: LocalRecurringRepository(db),
      budgets: LocalBudgetRepository(db),
      attachments: LocalAttachmentRepository(
        db,
        byteStore: MemoryAttachmentByteStore(),
      ),
      merchantRules: MerchantRuleStore(),
      filePort: filePort,
      deviceIdLoader: () async => 'recovery-drill-test-device',
      encryption: BackupEncryption.testing(),
      drillAudits: drillAudits,
    );
  }

  final AppDatabase db;
  late final LedgerRepository repository;
  late final InMemoryBackupFilePort filePort;
  late final BackupRecoveryDrillAuditStore drillAudits;
  late final BackupService service;

  Future<void> seed() => repository.seedIfEmpty();

  Future<void> close() => db.close();
}
