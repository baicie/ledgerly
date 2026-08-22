import 'dart:typed_data';

abstract class UserFilePort {
  Future<String?> pickCsvText();

  Future<PickedBinaryFile?> pickBinaryFile({bool imagesOnly = false});

  Future<void> saveTextFile({
    required String fileName,
    required String contents,
  });
}

class PickedBinaryFile {
  const PickedBinaryFile({
    required this.name,
    required this.bytes,
    required this.mime,
  });

  final String name;
  final Uint8List bytes;
  final String mime;
}

class UnsupportedUserFilePort implements UserFilePort {
  const UnsupportedUserFilePort();

  @override
  Future<PickedBinaryFile?> pickBinaryFile({bool imagesOnly = false}) async =>
      null;

  @override
  Future<String?> pickCsvText() async => null;

  @override
  Future<void> saveTextFile({
    required String fileName,
    required String contents,
  }) async {}
}

class MemoryUserFilePort implements UserFilePort {
  MemoryUserFilePort({
    this.csvText,
    this.binaryFile,
  });

  String? csvText;
  PickedBinaryFile? binaryFile;
  final savedFiles = <String, String>{};

  @override
  Future<String?> pickCsvText() async => csvText;

  @override
  Future<PickedBinaryFile?> pickBinaryFile({bool imagesOnly = false}) async =>
      binaryFile;

  @override
  Future<void> saveTextFile({
    required String fileName,
    required String contents,
  }) async {
    savedFiles[fileName] = contents;
  }
}
