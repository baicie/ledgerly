import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../application/csv_text.dart';
import 'user_file_port.dart';

class PluginUserFilePort implements UserFilePort {
  const PluginUserFilePort();

  @override
  Future<PickedBinaryFile?> pickBinaryFile({bool imagesOnly = false}) async {
    final file = await FilePicker.pickFile(
      type: imagesOnly ? FileType.image : FileType.any,
    );
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
    return decodeBillCsvBytes(await file.readAsBytes());
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
