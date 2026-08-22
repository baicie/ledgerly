import 'dart:typed_data';

abstract class AttachmentStore {
  Future<String> write({
    required String id,
    required Uint8List bytes,
  });

  Future<Uint8List?> read(String relativePath);

  Future<void> delete(String relativePath);
}

class MemoryAttachmentStore implements AttachmentStore {
  final files = <String, Uint8List>{};

  @override
  Future<void> delete(String relativePath) async {
    files.remove(relativePath);
  }

  @override
  Future<Uint8List?> read(String relativePath) async => files[relativePath];

  @override
  Future<String> write({
    required String id,
    required Uint8List bytes,
  }) async {
    final path = 'attachments/$id';
    files[path] = bytes;
    return path;
  }
}
