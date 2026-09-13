import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import 'backup_service.dart';

/// Identifiers written into the encrypted envelope's `kdf.algorithm`.
const String kKdfArgon2id = 'argon2id';
const String kKdfPbkdf2Sha256 = 'pbkdf2-sha256';

/// KDF parameters written into the encrypted backup's outer envelope.
/// Phase 11 defaults to Argon2id; Phase 10 files used PBKDF2-HMAC-SHA256.
/// The algorithm name is recorded explicitly so decrypt can branch.
@immutable
class KdfParams {
  const KdfParams({
    required this.algorithm,
    required this.iterations,
    required this.salt,
    required this.hashLengthBytes,
    this.memoryKb = 0,
    this.parallelism = 1,
  });

  /// `argon2id` (Phase 11 default) or `pbkdf2-sha256` (Phase 10).
  final String algorithm;

  /// Time cost. PBKDF2 round count, or Argon2id iterations.
  final int iterations;

  /// Random salt. Always base64-encoded inside the envelope JSON.
  final Uint8List salt;

  /// Derived-key length in bytes (32 for AES-256).
  final int hashLengthBytes;

  /// Argon2id memory in KiB. `0` for PBKDF2 envelopes.
  final int memoryKb;

  /// Argon2id parallelism. Ignored for PBKDF2.
  final int parallelism;

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'iterations': iterations,
        'salt': base64.encode(salt),
        'hashLengthBytes': hashLengthBytes,
        if (memoryKb > 0) 'memoryKb': memoryKb,
        if (algorithm == kKdfArgon2id) 'parallelism': parallelism,
      };

  static KdfParams fromJson(Map<String, dynamic> json) {
    final algorithm = json['algorithm'] as String? ?? kKdfPbkdf2Sha256;
    final iterations = (json['iterations'] as num?)?.toInt() ??
        (algorithm == kKdfArgon2id ? 2 : 600000);
    final saltRaw = json['salt'];
    if (saltRaw is! String) {
      throw BackupFormatException('KDF salt 缺失');
    }
    final salt = Uint8List.fromList(base64.decode(saltRaw));
    final hashLengthBytes = (json['hashLengthBytes'] as num?)?.toInt() ?? 32;
    return KdfParams(
      algorithm: algorithm,
      iterations: iterations,
      salt: salt,
      hashLengthBytes: hashLengthBytes,
      memoryKb: (json['memoryKb'] as num?)?.toInt() ?? 0,
      parallelism: (json['parallelism'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Carries everything the [BackupFilePort] needs to write the
/// encrypted outer container. The plaintext v2 payload lives only as
/// a length + sha256 so we can validate decryption; the encrypted
/// bytes themselves are stored alongside.
@immutable
class EncryptedPayload {
  const EncryptedPayload({
    required this.envelopeJson,
    required this.ciphertext,
    required this.kdf,
    required this.nonce,
    required this.authTag,
    required this.plaintextSize,
    required this.plaintextSha256Hex,
  });

  /// Bytes for `envelope.json` — the only cleartext file inside the
  /// outer zip. Holds KDF params + nonce + tag + size + sha256.
  final Uint8List envelopeJson;

  /// Bytes for `payload.enc` — AES-256-GCM ciphertext of the v2 zip.
  final Uint8List ciphertext;

  /// KDF parameters used to derive the key from the user password.
  final KdfParams kdf;

  /// AES-GCM nonce (12 bytes). Random per backup; never reused.
  final Uint8List nonce;

  /// AES-GCM authentication tag (16 bytes). Validates integrity.
  final Uint8List authTag;

  /// Plaintext v2 zip size in bytes (before compression / encryption).
  final int plaintextSize;

  /// Hex SHA-256 of the plaintext v2 zip. Verified after decryption.
  final String plaintextSha256Hex;
}

/// Pure-Dart encryption / decryption helpers used by [BackupService]
/// to wrap a v2 [BackupDocument] in a password-encrypted v3 envelope.
///
/// The flow:
///
///   plaintext = v2-zip-bytes(document)
///   key       = Argon2id(password, salt, memory, iter, parallelism)
///               (Phase 10 files: PBKDF2-HMAC-SHA256)
///   ciphertext, nonce, tag = AES-256-GCM(key).encrypt(plaintext)
///   envelope.json = { kdf, nonce, tag, plaintextSize, plaintextSha256 }
///   payload.enc   = ciphertext
///   outer-zip     = [envelope.json, payload.enc]
///
/// Phase 10 exposes this through [BackupService.export(password:)]
/// and [BackupService.restore(password:)]; the [BackupFilePort]
/// transparently materialises either the v2 zip or the v3 encrypted
/// outer zip depending on whether [BackupDocument.encrypted] is set.
class BackupEncryption {
  BackupEncryption({
    Random? random,
    this.kdfAlgorithm = kKdfArgon2id,
    this.pbkdf2Iterations = defaultPbkdf2Iterations,
    int? argon2MemoryKb,
    this.argon2Iterations = defaultArgon2Iterations,
    this.argon2Parallelism = defaultArgon2Parallelism,
  })  : _random = random ?? Random.secure(),
        argon2MemoryKb = argon2MemoryKb ?? defaultArgon2MemoryKb;

  /// Fast Argon2id parameters so widget / unit tests stay under a
  /// second. Production code must not use this constructor.
  BackupEncryption.testing({Random? random})
      : this(
          random: random,
          argon2MemoryKb: testingArgon2MemoryKb,
          argon2Iterations: 1,
          argon2Parallelism: 1,
        );

  final Random _random;

  /// Which KDF new backups use when the caller does not supply
  /// [KdfParams]. Decrypt still honors whatever the envelope recorded.
  final String kdfAlgorithm;

  /// PBKDF2 round count used when [kdfAlgorithm] is [kKdfPbkdf2Sha256].
  final int pbkdf2Iterations;

  /// Argon2id memory in KiB used when [kdfAlgorithm] is [kKdfArgon2id].
  final int argon2MemoryKb;

  final int argon2Iterations;
  final int argon2Parallelism;

  static const int defaultPbkdf2Iterations = 600000;
  static const int defaultHashLengthBytes = 32;
  static const int defaultArgon2Iterations = 2;
  static const int defaultArgon2Parallelism = 1;
  static const int defaultArgon2MemoryKbNative = 19456;
  static const int defaultArgon2MemoryKbWeb = 8192;
  static const int testingArgon2MemoryKb = 32;

  /// OWASP 2023 Argon2id memory on native; a smaller budget on web
  /// because the pure-Dart implementation is slower there.
  static int get defaultArgon2MemoryKb =>
      kIsWeb ? defaultArgon2MemoryKbWeb : defaultArgon2MemoryKbNative;

  /// Encrypt [plaintext] using a key derived from [password]. The
  /// returned [EncryptedPayload] carries everything the outer zip
  /// needs. [kdfParams] lets tests pin deterministic salts; defaults
  /// to a freshly-generated random salt.
  ///
  /// [publicMetadata] is copied into the cleartext envelope (summary,
  /// bookIds, attachmentIndex, exportedAt, deviceId) so a restore
  /// preview can render counts before the user types the password.
  Future<EncryptedPayload> encrypt(
    Uint8List plaintext, {
    required String password,
    KdfParams? kdfParams,
    Map<String, dynamic>? publicMetadata,
  }) async {
    if (password.length < 8) {
      throw ArgumentError.value(
        password.length,
        'password.length',
        '密码至少 8 位',
      );
    }

    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final params = kdfParams ?? _defaultKdfParams(salt);
    final keyBytes = await _deriveKey(password, params);
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );

    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(keyBytes);
    final nonceBytes = nonce;
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonceBytes,
    );
    final ciphertext = Uint8List.fromList(secretBox.cipherText);
    final authTag = Uint8List.fromList(secretBox.mac.bytes);

    final envelope = <String, dynamic>{
      ...?publicMetadata,
      'kind': 'ledgerly-backup-encrypted',
      'schemaVersion': kEncryptedBackupSchemaVersion,
      'encryption': {
        'kdf': params.toJson(),
        'cipher': 'aes-256-gcm',
        'nonce': base64.encode(nonce),
        'authTag': base64.encode(authTag),
        'plaintextSize': plaintext.length,
        'plaintextSha256': crypto.sha256.convert(plaintext).toString(),
      },
    };
    final envelopeBytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));

    return EncryptedPayload(
      envelopeJson: envelopeBytes,
      ciphertext: ciphertext,
      kdf: params,
      nonce: nonce,
      authTag: authTag,
      plaintextSize: plaintext.length,
      plaintextSha256Hex: envelope['encryption']['plaintextSha256'] as String,
    );
  }

  /// Decrypt the [EncryptedPayload] using the user-supplied [password].
  /// Throws [BackupPasswordException] when the AES-GCM authentication
  /// tag does not match (covers both wrong-password and tampered files);
  /// throws [BackupTamperedException] when the SHA-256 of the decrypted
  /// bytes does not match what the envelope declared.
  Future<Uint8List> decrypt(
    EncryptedPayload payload, {
    required String password,
  }) async {
    final keyBytes = await _deriveKey(password, payload.kdf);
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(keyBytes);
    final secretBox = SecretBox(
      payload.ciphertext,
      nonce: payload.nonce,
      mac: Mac(payload.authTag),
    );
    final Uint8List plaintext;
    try {
      plaintext = Uint8List.fromList(
        await algorithm.decrypt(secretBox, secretKey: secretKey),
      );
    } on SecretBoxAuthenticationError catch (error) {
      throw BackupPasswordException('备份密码错误：$error');
    } catch (error) {
      throw BackupPasswordException('备份密码错误：$error');
    }

    if (plaintext.length != payload.plaintextSize) {
      throw BackupTamperedException(
        '解密后长度(${plaintext.length})与 envelope 声明(${payload.plaintextSize})不一致',
      );
    }
    final actualSha = crypto.sha256.convert(plaintext).toString();
    if (actualSha != payload.plaintextSha256Hex) {
      throw BackupTamperedException(
        '解密后 SHA-256 不匹配，备份可能被篡改',
      );
    }
    return plaintext;
  }

  KdfParams _defaultKdfParams(Uint8List salt) {
    if (kdfAlgorithm == kKdfPbkdf2Sha256) {
      return KdfParams(
        algorithm: kKdfPbkdf2Sha256,
        iterations: pbkdf2Iterations,
        salt: salt,
        hashLengthBytes: defaultHashLengthBytes,
      );
    }
    return KdfParams(
      algorithm: kKdfArgon2id,
      iterations: argon2Iterations,
      salt: salt,
      hashLengthBytes: defaultHashLengthBytes,
      memoryKb: argon2MemoryKb,
      parallelism: argon2Parallelism,
    );
  }

  /// Derive a 32-byte AES-256 key from [password] + [params].
  /// Phase 11 prefers Argon2id; Phase 10 envelopes still hash with
  /// PBKDF2. Unknown algorithms are refused rather than guessed.
  Future<Uint8List> _deriveKey(String password, KdfParams params) async {
    switch (params.algorithm) {
      case kKdfPbkdf2Sha256:
        return _derivePbkdf2(password, params);
      case kKdfArgon2id:
        return _deriveArgon2id(password, params);
      default:
        throw BackupFormatException('不支持的 KDF：${params.algorithm}');
    }
  }

  Future<Uint8List> _derivePbkdf2(String password, KdfParams params) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: params.hashLengthBytes * 8,
    );
    final secretKey = SecretKey(utf8.encode(password));
    final newKey = await pbkdf2.deriveKey(
      secretKey: secretKey,
      nonce: params.salt,
    );
    return Uint8List.fromList(await newKey.extractBytes());
  }

  Future<Uint8List> _deriveArgon2id(
    String password,
    KdfParams params,
  ) async {
    final algorithm = Argon2id(
      parallelism: params.parallelism < 1 ? 1 : params.parallelism,
      memory: params.memoryKb < 8 ? 8 : params.memoryKb,
      iterations: params.iterations < 1 ? 1 : params.iterations,
      hashLength: params.hashLengthBytes,
    );
    final newKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: params.salt,
    );
    return Uint8List.fromList(await newKey.extractBytes());
  }
}

/// Raised when an encrypted backup cannot be opened because the user
/// supplied the wrong password (AES-GCM tag mismatch).
class BackupPasswordException extends BackupFormatException {
  const BackupPasswordException(super.message);
}

/// Raised when the envelope and the decrypted payload disagree about
/// size or SHA-256, suggesting the file was tampered with after
/// encryption.
class BackupTamperedException extends BackupFormatException {
  const BackupTamperedException(super.message);
}

/// Consecutive wrong-password attempts before the restore UI locks.
const int kBackupUnlockMaxAttempts = 3;

/// How long the restore UI stays locked after [kBackupUnlockMaxAttempts]
/// failed password submissions.
const Duration kBackupUnlockLockDuration = Duration(seconds: 30);
