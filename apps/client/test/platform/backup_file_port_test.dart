import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/platform/atomic_file_writer.dart';
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
    expect(
      directory.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('failed atomic write preserves the existing file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ledgerly-atomic-writer-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/backup.zip');
    await target.writeAsString('original', flush: true);
    final writer = AtomicFileWriter(
      writer: (file, bytes) async {
        await file.writeAsBytes(bytes.take(1).toList(), flush: true);
        throw StateError('disk full');
      },
    );

    await expectLater(
      writer.write(target, [1, 2, 3]),
      throwsA(isA<StateError>()),
    );

    expect(await target.readAsString(), 'original');
    expect(
      directory.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('failed atomic rename preserves the existing file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ledgerly-atomic-rename-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/backup.zip');
    await target.writeAsString('original', flush: true);
    final writer = AtomicFileWriter(
      mover: (file, newPath) => throw StateError('rename failed'),
    );

    await expectLater(
      writer.write(target, [1, 2, 3]),
      throwsA(isA<StateError>()),
    );

    expect(await target.readAsString(), 'original');
    expect(
      directory.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('successful atomic write replaces the file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ledgerly-atomic-success-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/backup.zip');
    await target.writeAsString('old', flush: true);

    await AtomicFileWriter().write(target, [110, 101, 119]);

    expect(await target.readAsString(), 'new');
    expect(
      directory.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('governance report is written atomically', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ledgerly-governance-report-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final port = PluginBackupFilePort(
      documentsDirectoryLoader: () async => directory,
    );

    final path = await port.writeGovernanceReport(
      '{"health":"healthy"}',
      extension: 'json',
    );

    expect(path, endsWith('.json'));
    expect(await File(path).readAsString(), '{"health":"healthy"}');
    expect(
      directory.listSync().where((entry) => entry.path.contains('.tmp-')),
      isEmpty,
    );
  });

  test('backup is mirrored atomically into an external directory', () async {
    final root = await Directory.systemTemp.createTemp(
      'ledgerly-mirror-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/ledgerly-source.ledgerly.zip');
    final external = Directory('${root.path}/external')..createSync();
    await source.writeAsBytes([1, 2, 3], flush: true);
    final port = PluginBackupFilePort(
      documentsDirectoryLoader: () async => root,
    );

    final target = await port.mirrorBackup(source.path, external.path);

    expect(await File(target).readAsBytes(), [1, 2, 3]);
    expect(await port.isBackupDirectoryAvailable(external.path), isTrue);
    final listed = await port.listBackupFiles(external.path);
    expect(listed, hasLength(1));
    expect(await File(listed.single).readAsBytes(), [1, 2, 3]);
    final imported = await port.importBackupFile(target);
    expect(imported, startsWith(root.path));
    expect(await File(imported).readAsBytes(), [1, 2, 3]);
    expect(
      root.listSync(recursive: true).where(
            (entry) => entry.path.contains('.tmp-'),
          ),
      isEmpty,
    );
  });
}
