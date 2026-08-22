import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'user_file_port.dart';

class PluginUserFilePort implements UserFilePort {
  const PluginUserFilePort();

  @override
  Future<PickedBinaryFile?> pickBinaryFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    return PickedBinaryFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      mime: _mime(_extension(file.name)),
    );
  }

  @override
  Future<String?> pickCsvText() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    if (file == null) return null;
    return _decodeText(await file.readAsBytes());
  }

  @override
  Future<void> saveTextFile({
    required String fileName,
    required String contents,
  }) async {
    final bytes = utf8.encode(contents);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'text/csv',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

  String _decodeText(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    return utf8.decode(bytes);
  }

  String _extension(String name) {
    final index = name.lastIndexOf('.');
    if (index <= 0 || index == name.length - 1) return '';
    return name.substring(index + 1);
  }

  String _mime(String extension) {
    return switch (extension.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }
}

UserFilePort createPlatformUserFilePort() => const PluginUserFilePort();
