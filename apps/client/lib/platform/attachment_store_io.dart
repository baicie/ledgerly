import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'attachment_store.dart';

class IoAttachmentStore implements AttachmentStore {
  @override
  Future<void> delete(String relativePath) async {
    final file = await _file(relativePath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Uint8List?> read(String relativePath) async {
    final file = await _file(relativePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<String> write({
    required String id,
    required Uint8List bytes,
  }) async {
    final relativePath = 'attachments/$id';
    final file = await _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return relativePath;
  }

  Future<File> _file(String relativePath) async {
    final root = await getApplicationDocumentsDirectory();
    return File(p.join(root.path, relativePath));
  }
}

AttachmentStore createPlatformAttachmentStore() => IoAttachmentStore();
