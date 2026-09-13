import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../application/backup_encryption.dart';
import '../application/backup_service.dart';
import 'atomic_file_writer.dart';

/// File-system boundary for backup I/O. The [BackupFilePort] contract
/// lives in `backup_service.dart`; this file supplies the platform
/// implementation and the in-memory test double.
///
/// Phase 10 adds:
///   * `buildPlaintextZip` — used by [BackupService] to seal a v2
///     payload inside a password-encrypted envelope without going
///     through the filesystem.
///   * `parsePlaintextZip` — the inverse, used after decryption so the
///     service can hand the unwrapped document straight to `restore`.
class PluginBackupFilePort implements BackupFilePort {
  PluginBackupFilePort({
    Future<Directory> Function()? documentsDirectoryLoader,
    AtomicFileWriter? atomicWriter,
  })  : _documentsDirectoryLoader =
            documentsDirectoryLoader ?? getApplicationDocumentsDirectory,
        _atomicWriter = atomicWriter ?? AtomicFileWriter();

  final Future<Directory> Function() _documentsDirectoryLoader;
  final AtomicFileWriter _atomicWriter;

  /// Pattern used to build user-facing filenames. Kept as a getter so
  /// tests can stub [DateTime.now] if they ever need a deterministic
  /// stamp.
  String _timestamp() {
    final now = DateTime.now().toUtc();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    return '$y-$m-${d}_$h$mi';
  }

  String _backupIdSuffix(BackupDocument document) {
    final backupId = document.backupId;
    if (backupId == null || backupId.isEmpty) return '';
    final length = backupId.length < 8 ? backupId.length : 8;
    return '-${backupId.substring(0, length)}';
  }

  String _exportFileName(String suffix) =>
      'ledgerly-backup-${_timestamp()}$suffix.ledgerly.zip';

  String _exportEncryptedFileName(String suffix) =>
      'ledgerly-backup-${_timestamp()}$suffix.ledgerly.enc.zip';

  String _exportIncrementalFileName(String suffix) =>
      'ledgerly-incremental-${_timestamp()}$suffix.ledgerly.inc.zip';

  String _safetyFileName(String suffix) =>
      'ledgerly-pre-restore-${_timestamp()}$suffix.ledgerly.zip';

  String _reportFileName(String extension) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'ledgerly-governance-${_timestamp()}-$micros.$extension';
  }

  @override
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    final dir = await _documentsDirectoryLoader();
    final isEncrypted = document.encrypted != null;
    final suffix = _backupIdSuffix(document);
    final fileName = isEncrypted
        ? _exportEncryptedFileName(suffix)
        : document.isIncremental
            ? _exportIncrementalFileName(suffix)
            : _exportFileName(suffix);
    final file = File('${dir.path}/$fileName');
    final bytes = isEncrypted
        ? _buildEncryptedZipBytes(document)
        : _buildZipBytes(document, deviceId: deviceId);
    await _atomicWriter.write(file, bytes);
    return file.path;
  }

  @override
  Future<String> writePreRestoreSafetyBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    final dir = await _documentsDirectoryLoader();
    final file = File(
      '${dir.path}/${_safetyFileName(_backupIdSuffix(document))}',
    );
    final bytes = _buildZipBytes(document, deviceId: deviceId);
    await _atomicWriter.write(file, bytes);
    return file.path;
  }

  @override
  Future<BackupDocument> readBackup(String source, {String? password}) async {
    final file = File(source);
    if (!await file.exists()) {
      throw BackupFormatException('备份文件不存在：$source');
    }
    final bytes = await file.readAsBytes();
    return await _decodeOuterZip(bytes, password: password);
  }

  @override
  Future<Uint8List> buildPlaintextZip(
    BackupDocument document, {
    required String deviceId,
  }) async {
    return _buildZipBytes(document, deviceId: deviceId);
  }

  @override
  BackupDocument parsePlaintextZip(Uint8List bytes) {
    return _decodeZipBytes(bytes);
  }

  @override
  Future<String?> pickBackupSource() async {
    final result = await FilePicker.pickFile(
      type: FileType.any,
    );
    if (result == null) return null;
    return result.path;
  }

  @override
  Future<String?> shareBackup(String source) async {
    final file = XFile(source, mimeType: 'application/zip');
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [_basename(source)],
      ),
    );
    return _basename(source);
  }

  @override
  Future<int> fileSize(String source) async {
    final file = File(source);
    return await file.exists() ? file.length() : 0;
  }

  @override
  Future<String?> fileSha256(String source) async {
    final file = File(source);
    if (!await file.exists()) return null;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  @override
  Future<void> deleteBackup(String source) async {
    final file = File(source);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<String> writeGovernanceReport(
    String contents, {
    required String extension,
  }) async {
    final dir = await _documentsDirectoryLoader();
    final file = File('${dir.path}/${_reportFileName(extension)}');
    await _atomicWriter.write(file, utf8.encode(contents));
    return file.path;
  }

  String _basename(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }
}

/// Build a zip container from a [BackupDocument]. Layout:
///
///   manifest.json        — JSON envelope (kind, schemaVersion,
///                           exportedAt, deviceId, summary, attachmentIndex)
///   data.json            -- the versioned `data` payload
///   attachments/{id}.bin -- raw attachment bytes, one entry per index
///
/// Used by both the platform port and the in-memory test port.
Uint8List _buildZipBytes(
  BackupDocument document, {
  required String deviceId,
}) {
  final manifest = document.toEnvelope(deviceId: deviceId);
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final dataBytes = utf8.encode(jsonEncode(document.payload));

  final archive = Archive();
  archive.addFile(_jsonFile('manifest.json', manifestBytes));
  archive.addFile(_jsonFile('data.json', dataBytes));
  for (final binary in document.attachmentBinaries) {
    archive.addFile(
      ArchiveFile(
        'attachments/${binary.id}.bin',
        binary.bytes.length,
        binary.bytes,
      ),
    );
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw const BackupFormatException('zip 编码失败');
  }
  return Uint8List.fromList(encoded);
}

/// Decode a zip container produced by [_buildZipBytes] into a
/// [BackupDocument]. Throws [BackupFormatException] when the container
/// is missing the manifest or when the manifest itself is invalid.
BackupDocument _decodeZipBytes(Uint8List bytes) {
  Archive? archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (error) {
    throw BackupFormatException('备份文件不是合法 zip：$error');
  }

  final manifestFile = archive.files.firstWhere(
    (file) => file.name == 'manifest.json',
    orElse: () => throw const BackupFormatException('备份缺少 manifest.json'),
  );
  Map<String, dynamic> envelope;
  try {
    final raw = utf8.decode(_readBytes(manifestFile));
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const BackupFormatException('manifest 不是 JSON 对象');
    }
    envelope = Map<String, dynamic>.from(decoded);
  } on BackupFormatException {
    rethrow;
  } catch (error) {
    throw BackupFormatException('manifest 解析失败：$error');
  }

  final document = BackupDocument.fromEnvelope(envelope);

  final dataFile = archive.files.firstWhere(
    (file) => file.name == 'data.json',
    orElse: () => throw const BackupFormatException('备份缺少 data.json'),
  );
  // Trust the manifest's payload (already validated) but cross-check
  // that the data.json on disk matches what the manifest declares. If
  // they disagree we refuse to restore rather than silently picking
  // one source.
  try {
    final raw = utf8.decode(_readBytes(dataFile));
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const BackupFormatException('data.json 不是 JSON 对象');
    }
    if (jsonEncode(decoded) != jsonEncode(document.payload)) {
      throw const BackupFormatException('manifest 与 data.json 不一致');
    }
  } on BackupFormatException {
    rethrow;
  } catch (error) {
    throw BackupFormatException('data.json 解析失败：$error');
  }

  final binaries = <AttachmentBinary>[];
  for (final file in archive.files) {
    if (!file.name.startsWith('attachments/')) continue;
    if (!file.name.endsWith('.bin')) continue;
    final fileName = file.name.substring('attachments/'.length);
    final id = fileName.substring(0, fileName.length - '.bin'.length);
    binaries.add(
      AttachmentBinary(
        id: id,
        bytes: Uint8List.fromList(_readBytes(file)),
      ),
    );
  }
  return document.withBinaries(binaries);
}

ArchiveFile _jsonFile(String name, List<int> bytes) {
  return ArchiveFile(name, bytes.length, bytes);
}

/// Pull raw bytes out of an [ArchiveFile]. The [content] getter
/// returns whatever shape the encoder chose (typically `Uint8List`
/// but the package leaves the door open for `List<int>`).
List<int> _readBytes(ArchiveFile file) {
  final content = file.content;
  if (content is Uint8List) return content;
  if (content is List<int>) return content;
  throw BackupFormatException('zip 条目字节无法读取：${file.name}');
}

// ----------------------------------------------------------------------
// Phase 10: password-encrypted outer container
// ----------------------------------------------------------------------

/// Pack an encrypted v3 outer zip from a [BackupDocument] whose
/// [EncryptedPayload] is already populated. Layout:
///
///   envelope.json  ← cleartext (KDF params + nonce + tag + size + sha256)
///   payload.enc    ← AES-256-GCM ciphertext of the v2-zip bytes
Uint8List _buildEncryptedZipBytes(BackupDocument document) {
  final encrypted = document.encrypted;
  if (encrypted == null) {
    throw BackupFormatException('加密备份缺少 EncryptedPayload');
  }
  final archive = Archive();
  archive.addFile(
    ArchiveFile(
      'envelope.json',
      encrypted.envelopeJson.length,
      encrypted.envelopeJson,
    ),
  );
  archive.addFile(
    ArchiveFile(
      'payload.enc',
      encrypted.ciphertext.length,
      encrypted.ciphertext,
    ),
  );
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw const BackupFormatException('加密 zip 编码失败');
  }
  return Uint8List.fromList(encoded);
}

/// Read a v1 JSON, v2 zip, or v3 encrypted zip and return the parsed
/// [BackupDocument]. For v3 containers the caller may omit [password]
/// to receive the locked shell (summary only); supplying it unwraps
/// the inner v2 snapshot immediately.
Future<BackupDocument> _decodeOuterZip(
  Uint8List bytes, {
  String? password,
}) async {
  Archive? archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (error) {
    return _decodeLegacyJson(bytes, zipError: error);
  }

  final hasEnvelope = archive.files.any((f) => f.name == 'envelope.json');
  final hasManifest = archive.files.any((f) => f.name == 'manifest.json');
  if (!hasEnvelope && !hasManifest) {
    return _decodeLegacyJson(bytes);
  }
  if (!hasEnvelope) {
    // v2 plaintext zip: manifest.json + data.json + attachments/.
    return _decodeZipBytes(bytes);
  }

  // v3 encrypted outer zip.
  final envelopeFile = archive.files.firstWhere(
    (f) => f.name == 'envelope.json',
    orElse: () => throw const BackupFormatException('加密备份缺少 envelope.json'),
  );
  final payloadFile = archive.files.firstWhere(
    (f) => f.name == 'payload.enc',
    orElse: () => throw const BackupFormatException('加密备份缺少 payload.enc'),
  );

  Map<String, dynamic> envelopeJson;
  try {
    final raw = utf8.decode(_readBytes(envelopeFile));
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const BackupFormatException('envelope.json 不是 JSON 对象');
    }
    envelopeJson = Map<String, dynamic>.from(decoded);
  } catch (error) {
    throw BackupFormatException('envelope.json 解析失败：$error');
  }
  if (envelopeJson['kind'] != 'ledgerly-backup-encrypted') {
    throw BackupFormatException(
      'envelope kind 异常：${envelopeJson['kind']}',
    );
  }

  final encryption = envelopeJson['encryption'];
  if (encryption is! Map) {
    throw const BackupFormatException('envelope 缺少 encryption 字段');
  }
  final encMap = Map<String, dynamic>.from(encryption);
  final kdfRaw = encMap['kdf'];
  if (kdfRaw is! Map) {
    throw const BackupFormatException('envelope kdf 缺失');
  }
  final kdf = KdfParams.fromJson(Map<String, dynamic>.from(kdfRaw));
  final cipher = encMap['cipher'] as String? ?? 'aes-256-gcm';
  if (cipher != 'aes-256-gcm') {
    throw BackupFormatException('不支持的加密算法：$cipher');
  }
  final nonceRaw = encMap['nonce'];
  if (nonceRaw is! String) {
    throw const BackupFormatException('envelope nonce 缺失');
  }
  final tagRaw = encMap['authTag'];
  if (tagRaw is! String) {
    throw const BackupFormatException('envelope authTag 缺失');
  }
  final plaintextSize = (encMap['plaintextSize'] as num?)?.toInt();
  if (plaintextSize == null) {
    throw const BackupFormatException('envelope plaintextSize 缺失');
  }
  final plaintextSha = encMap['plaintextSha256'] as String?;
  if (plaintextSha == null) {
    throw const BackupFormatException('envelope plaintextSha256 缺失');
  }

  final encrypted = EncryptedPayload(
    envelopeJson: Uint8List.fromList(_readBytes(envelopeFile)),
    ciphertext: Uint8List.fromList(_readBytes(payloadFile)),
    kdf: kdf,
    nonce: Uint8List.fromList(base64.decode(nonceRaw)),
    authTag: Uint8List.fromList(base64.decode(tagRaw)),
    plaintextSize: plaintextSize,
    plaintextSha256Hex: plaintextSha,
  );

  // Build a "shell" BackupDocument whose payload / attachmentIndex are
  // taken from the (intentionally minimal) envelope.json so the
  // restore preview can render summary counts without needing the
  // password. The decryption path replaces these fields once the
  // password unlocks the ciphertext.
  final envelopeSummary = envelopeJson['summary'];
  final summary = envelopeSummary is Map
      ? BackupSummary.fromJson(Map<String, dynamic>.from(envelopeSummary))
      : const BackupSummary(
          books: 0,
          accounts: 0,
          transactions: 0,
          transactionEntries: 0,
          recurringRules: 0,
          budgets: 0,
          attachments: 0,
          merchantRules: 0,
        );
  final rawBookIds = envelopeJson['bookIds'];
  final bookIds =
      rawBookIds is List ? rawBookIds.whereType<String>().toSet() : null;
  final rawIndex = envelopeJson['attachmentIndex'];
  final attachmentIndex = rawIndex is List
      ? rawIndex
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : const <Map<String, dynamic>>[];

  if (password != null && password.isNotEmpty) {
    final plaintext = await BackupEncryption().decrypt(
      encrypted,
      password: password,
    );
    return _decodeZipBytes(plaintext);
  }

  return BackupDocument(
    summary: summary,
    payload: const {},
    bookIds: bookIds,
    attachmentIndex: attachmentIndex,
    encrypted: encrypted,
    schemaVersion: kEncryptedBackupSchemaVersion,
  );
}

BackupDocument _decodeLegacyJson(Uint8List bytes, {Object? zipError}) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map) {
      return BackupDocument.fromEnvelope(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {}
  throw BackupFormatException(
    zipError == null ? '备份文件无法识别' : '备份文件不是合法 zip：$zipError',
  );
}

/// Convenience factory so the rest of the app does not need to import
/// `package:path_provider` directly.
BackupFilePort createPlatformBackupFilePort() => PluginBackupFilePort();

/// In-memory port for tests. Records every operation so assertions can
/// inspect what the page asked the port to do without touching disk.
class InMemoryBackupFilePort implements BackupFilePort {
  InMemoryBackupFilePort({
    Map<String, BackupDocument>? envelopes,
    this.pickResult,
  })  : envelopes = envelopes ?? <String, BackupDocument>{},
        rawFiles = <String, Uint8List>{},
        reportFiles = <String, String>{};

  /// Stored envelopes keyed by the source identifier returned by
  /// [writeBackup] / [writePreRestoreSafetyBackup]. Defaults to an
  /// empty mutable map so callers can write into it without first
  /// supplying their own instance.
  Map<String, BackupDocument> envelopes;

  /// Raw zip bytes that were written, keyed by source identifier. Kept
  /// separate from [envelopes] so tests can assert the on-disk container
  /// shape (manifest.json + attachments/{id}.bin) without rebuilding it
  /// in memory.
  Map<String, Uint8List> rawFiles;

  /// Governance reports written during tests, keyed by returned id.
  Map<String, String> reportFiles;

  /// What [pickBackupSource] returns. `null` means the user cancelled.
  String? pickResult;

  /// Counter so each write returns a unique auto-incrementing id when
  /// callers don't supply their own.
  int _counter = 0;

  @override
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    final id = 'memory-backup-${++_counter}';
    envelopes[id] = document;
    rawFiles[id] = document.encrypted != null
        ? _buildEncryptedZipBytes(document)
        : _buildZipBytes(document, deviceId: deviceId);
    return id;
  }

  @override
  Future<String> writePreRestoreSafetyBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    final id = 'memory-safety-${++_counter}';
    envelopes[id] = document;
    rawFiles[id] = _buildZipBytes(document, deviceId: deviceId);
    return id;
  }

  @override
  Future<BackupDocument> readBackup(String source, {String? password}) async {
    final raw = rawFiles[source];
    if (raw != null) {
      return await _decodeOuterZip(raw, password: password);
    }
    final doc = envelopes[source];
    if (doc == null) {
      throw BackupFormatException('InMemoryBackupFilePort: missing $source');
    }
    return doc;
  }

  @override
  Future<String?> pickBackupSource() async => pickResult;

  @override
  Future<String?> shareBackup(String source) async => source;

  @override
  Future<int> fileSize(String source) async {
    final raw = rawFiles[source];
    if (raw != null) return raw.length;
    return envelopes.containsKey(source) ? 1 : 0;
  }

  @override
  Future<String?> fileSha256(String source) async {
    final raw = rawFiles[source];
    return raw == null ? null : sha256.convert(raw).toString();
  }

  @override
  Future<void> deleteBackup(String source) async {
    rawFiles.remove(source);
    envelopes.remove(source);
    reportFiles.remove(source);
  }

  @override
  Future<String> writeGovernanceReport(
    String contents, {
    required String extension,
  }) async {
    final id = 'memory-report-${++_counter}.$extension';
    reportFiles[id] = contents;
    return id;
  }

  @override
  Future<Uint8List> buildPlaintextZip(
    BackupDocument document, {
    required String deviceId,
  }) async {
    return _buildZipBytes(document, deviceId: deviceId);
  }

  @override
  BackupDocument parsePlaintextZip(Uint8List bytes) {
    return _decodeZipBytes(bytes);
  }
}
