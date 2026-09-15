import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_catalog_store.dart';
import 'package:ledgerly_client/application/backup_metadata_store.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/platform/atomic_file_writer.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('failed platform write leaves metadata and catalog untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'ledgerly-atomic-service-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'atomic-test-device',
    );
    await repository.seedIfEmpty();
    final metadata = BackupMetadataStore();
    final catalog = BackupCatalogStore();
    final filePort = PluginBackupFilePort(
      documentsDirectoryLoader: () async => directory,
      atomicWriter: AtomicFileWriter(
        writer: (file, bytes) => throw StateError('disk full'),
      ),
    );
    final service = BackupService(
      database: database,
      recurring: LocalRecurringRepository(database),
      budgets: LocalBudgetRepository(database),
      attachments: LocalAttachmentRepository(
        database,
        byteStore: MemoryAttachmentByteStore(),
      ),
      merchantRules: MerchantRuleStore(),
      filePort: filePort,
      deviceIdLoader: () async => 'atomic-test-device',
      metadata: metadata,
      catalog: catalog,
    );

    await expectLater(
      service.exportToFile(),
      throwsA(isA<StateError>()),
    );

    expect((await metadata.read()).lastBackupAt, isNull);
    expect(await catalog.read(), isEmpty);
    expect(
      directory.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });
}
