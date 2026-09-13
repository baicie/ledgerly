import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ledgerly_client/application/backup_encryption.dart';
import 'package:ledgerly_client/application/backup_service.dart';
import 'package:ledgerly_client/application/merchant_rule_store.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/data/local_attachment_repository.dart';
import 'package:ledgerly_client/data/local_budget_repository.dart';
import 'package:ledgerly_client/data/local_recurring_repository.dart';
import 'package:ledgerly_client/platform/backup_file_port.dart';

void main() {
  const password = 'correct-password';
  final encryption = BackupEncryption.testing();

  group('BackupEncryption', () {
    test('defaults new backups to Argon2id', () async {
      final plaintext = Uint8List.fromList(utf8.encode('ledgerly-secret'));
      final sealed = await encryption.encrypt(plaintext, password: password);
      expect(sealed.kdf.algorithm, kKdfArgon2id);
      expect(sealed.kdf.memoryKb, BackupEncryption.testingArgon2MemoryKb);
      expect(sealed.kdf.parallelism, 1);
      expect(sealed.kdf.iterations, 1);
      expect(BackupEncryption.defaultArgon2MemoryKbNative, 19456);
    });

    test('round-trips plaintext bytes with AES-256-GCM', () async {
      final plaintext = Uint8List.fromList(utf8.encode('ledgerly-secret'));
      final sealed = await encryption.encrypt(plaintext, password: password);
      expect(sealed.nonce, hasLength(12));
      expect(sealed.authTag, hasLength(16));

      final opened = await encryption.decrypt(sealed, password: password);
      expect(opened, equals(plaintext));
    });

    test('still decrypts Phase 10 PBKDF2 envelopes', () async {
      final plaintext = Uint8List.fromList(utf8.encode('ledgerly-secret'));
      final legacy = BackupEncryption(
        kdfAlgorithm: kKdfPbkdf2Sha256,
        pbkdf2Iterations: 100,
      );
      final sealed = await legacy.encrypt(plaintext, password: password);
      expect(sealed.kdf.algorithm, kKdfPbkdf2Sha256);

      final opened = await encryption.decrypt(sealed, password: password);
      expect(opened, equals(plaintext));
    });

    test('rejects unknown KDF algorithms', () async {
      final plaintext = Uint8List.fromList(utf8.encode('ledgerly-secret'));
      final sealed = await encryption.encrypt(plaintext, password: password);
      final unsupported = EncryptedPayload(
        envelopeJson: sealed.envelopeJson,
        ciphertext: sealed.ciphertext,
        kdf: KdfParams(
          algorithm: 'scrypt',
          iterations: 1,
          salt: sealed.kdf.salt,
          hashLengthBytes: 32,
        ),
        nonce: sealed.nonce,
        authTag: sealed.authTag,
        plaintextSize: sealed.plaintextSize,
        plaintextSha256Hex: sealed.plaintextSha256Hex,
      );
      await expectLater(
        encryption.decrypt(unsupported, password: password),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects passwords shorter than 8 characters', () async {
      final plaintext = Uint8List.fromList(utf8.encode('x'));
      await expectLater(
        encryption.encrypt(plaintext, password: 'short'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('wrong password raises BackupPasswordException', () async {
      final plaintext = Uint8List.fromList(utf8.encode('ledgerly-secret'));
      final sealed = await encryption.encrypt(plaintext, password: password);
      await expectLater(
        encryption.decrypt(sealed, password: 'wrong-password'),
        throwsA(isA<BackupPasswordException>()),
      );
    });

    test('tampered SHA-256 raises BackupTamperedException', () async {
      final plaintext = Uint8List.fromList(utf8.encode('ledgerly-secret'));
      final sealed = await encryption.encrypt(plaintext, password: password);
      final tampered = EncryptedPayload(
        envelopeJson: sealed.envelopeJson,
        ciphertext: sealed.ciphertext,
        kdf: sealed.kdf,
        nonce: sealed.nonce,
        authTag: sealed.authTag,
        plaintextSize: sealed.plaintextSize,
        plaintextSha256Hex: '00' * 32,
      );
      await expectLater(
        encryption.decrypt(tampered, password: password),
        throwsA(isA<BackupTamperedException>()),
      );
    });
  });

  group('BackupService password envelope', () {
    late AppDatabase database;
    late BackupService backupService;
    late InMemoryBackupFilePort filePort;
    late LocalAttachmentRepository attachments;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase.forTesting(NativeDatabase.memory());
      final ledgerRepository = LedgerRepository(
        database,
        deviceIdLoader: () async => 'encryption-test-device',
      );
      await ledgerRepository.seedIfEmpty();
      attachments = LocalAttachmentRepository(
        database,
        byteStore: MemoryAttachmentByteStore(),
      );
      filePort = InMemoryBackupFilePort();
      backupService = BackupService(
        database: database,
        recurring: LocalRecurringRepository(database),
        budgets: LocalBudgetRepository(database),
        attachments: attachments,
        merchantRules: MerchantRuleStore(),
        filePort: filePort,
        deviceIdLoader: () async => 'encryption-test-device',
        encryption: encryption,
      );
    });

    tearDown(() => database.close());

    test('default export writes a plaintext v2 zip', () async {
      final path = await backupService.exportToFile();
      final raw = filePort.rawFiles[path]!;
      final archive = ZipDecoder().decodeBytes(raw);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(['manifest.json', 'data.json']));
      expect(names, isNot(contains('envelope.json')));
      expect(filePort.envelopes[path]!.encrypted, isNull);
    });

    test('password export writes an encrypted outer zip', () async {
      final path = await backupService.exportToFile(password: password);
      final document = filePort.envelopes[path]!;
      expect(document.encrypted, isNotNull);

      final raw = filePort.rawFiles[path]!;
      final archive = ZipDecoder().decodeBytes(raw);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(['envelope.json', 'payload.enc']));
      expect(names, isNot(contains('manifest.json')));

      final envelopeFile = archive.files.firstWhere(
        (f) => f.name == 'envelope.json',
      );
      final envelope = jsonDecode(
        utf8.decode(
          envelopeFile.content is List<int>
              ? envelopeFile.content as List<int>
              : (envelopeFile.content as Uint8List),
        ),
      ) as Map<String, dynamic>;
      expect(envelope['kind'], 'ledgerly-backup-encrypted');
      expect(envelope['schemaVersion'], kEncryptedBackupSchemaVersion);
      expect(envelope['summary'], isA<Map>());
      final kdf = (envelope['encryption'] as Map)['kdf'] as Map;
      expect(kdf['algorithm'], kKdfArgon2id);
      expect(kdf['memoryKb'], BackupEncryption.testingArgon2MemoryKb);
    });

    test('correct password restores the original snapshot', () async {
      final original = await backupService.export();
      final path = await backupService.exportToFile(password: password);
      await backupService.wipeLocalData();

      final locked = await filePort.readBackup(path);
      expect(locked.isEncrypted, isTrue);
      expect(locked.payload, isEmpty);

      final unlocked = await backupService.unlockEncrypted(
        locked,
        password: password,
      );
      expect(unlocked.isEncrypted, isFalse);
      expect(unlocked.payload['books'], isNotEmpty);

      await backupService.restore(unlocked);
      final restored = await backupService.export();
      expect(restored.summary.books, original.summary.books);
      expect(restored.summary.accounts, original.summary.accounts);
    });

    test('wrong password does not restore', () async {
      final path = await backupService.exportToFile(password: password);
      final locked = await filePort.readBackup(path);
      await expectLater(
        backupService.unlockEncrypted(
          locked,
          password: 'wrong-password',
        ),
        throwsA(isA<BackupPasswordException>()),
      );
    });
  });
}
