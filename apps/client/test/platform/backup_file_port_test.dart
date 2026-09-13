import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  test('backup filenames include a backup id suffix', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ledgerly-backup-port-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final port = PluginBackupFilePort(
      documentsDirectoryLoader: () async => directory,
    );
    final first = BackupDocument(
      summary: const BackupSummary(
        books: 0,
        accounts: 0,
        transactions: 0,
        transactionEntries: 0,
        recurringRules: 0,
        budgets: 0,
        attachments: 0,
        merchantRules: 0,
      ),
      payload: const {},
      backupId: '11111111-1111-4111-8111-111111111111',
    );
    final second = first.withBackupId(
      '22222222-2222-4222-8222-222222222222',
    );

    final firstPath = await port.writeBackup(
      first,
      deviceId: 'test-device',
    );
    final secondPath = await port.writeBackup(
      second,
      deviceId: 'test-device',
    );

    expect(firstPath, contains('11111111'));
    expect(secondPath, contains('22222222'));
    expect(firstPath, isNot(secondPath));
  });
}
