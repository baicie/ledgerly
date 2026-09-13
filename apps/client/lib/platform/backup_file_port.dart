import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../application/backup_service.dart';

/// Default implementation of [BackupFilePort] that talks to the
/// filesystem + system share sheet. Tests inject an in-memory port so
/// they can assert envelope shape without touching disk.
class PluginBackupFilePort implements BackupFilePort {
  const PluginBackupFilePort({
    Future<Directory> Function()? documentsDirectoryLoader,
  }) : _documentsDirectoryLoader =
            documentsDirectoryLoader ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectoryLoader;

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

  String _exportFileName() =>
      'ledgerly-backup-$_timestamp.ledgerly.zip';

  String _safetyFileName() =>
      'ledgerly-pre-restore-$_timestamp.ledgerly.zip';

  @override
  Future<String> writeBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    final dir = await _documentsDirectoryLoader();
    final file = File('${dir.path}/${_exportFileName()}');
    final bytes = _buildZipBytes(document, deviceId: deviceId);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<String> writePreRestoreSafetyBackup(
    BackupDocument document, {
    required String deviceId,
  }) async {
    final dir = await _documentsDirectoryLoader();
    final file = File('${dir.path}/${_safetyFileName()}');
    final bytes = _buildZipBytes(document, deviceId: deviceId);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<BackupDocument> readBackup(String source) async {
    final file = File(source);
    if (!await file.exists()) {
      throw BackupFormatException('备份文件不存在：$source');
    }
    final bytes = await file.readAsBytes();
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

/// Convenience factory so the rest of the app does not need to import
/// `package:path_provider` directly.
BackupFilePort createPlatformBackupFilePort() => const PluginBackupFilePort();

/// In-memory port for tests. Records every operation so assertions can
/// inspect what the page asked the port to do without touching disk.
class InMemoryBackupFilePort implements BackupFilePort {
  InMemoryBackupFilePort({
    Map<String, BackupDocument>? envelopes,
    this.pickResult,
  }) : envelopes = envelopes ?? <String, BackupDocument>{},
       rawFiles = <String, Uint8List>{};

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
    rawFiles[id] = _buildZipBytes(document, deviceId: deviceId);
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
  Future<BackupDocument> readBackup(String source) async {
    final raw = rawFiles[source];
    if (raw != null) {
      return _decodeZipBytes(raw);
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
}