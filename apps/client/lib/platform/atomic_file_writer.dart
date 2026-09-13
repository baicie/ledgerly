import 'dart:io';

typedef AtomicBytesWriter = Future<void> Function(
  File file,
  List<int> bytes,
);

typedef AtomicFileMover = Future<File> Function(
  File file,
  String newPath,
);

typedef AtomicTempPathBuilder = String Function(File target);

/// Writes bytes to a temporary file in the target directory and only
/// replaces [File] after the complete write succeeds.
///
/// The writer and mover are injectable so tests can simulate partial
/// writes and rename failures without relying on OS permissions.
class AtomicFileWriter {
  AtomicFileWriter({
    AtomicBytesWriter? writer,
    AtomicFileMover? mover,
    AtomicTempPathBuilder? tempPathBuilder,
  })  : _writer = writer ?? _writeBytes,
        _mover = mover ?? _rename,
        _tempPathBuilder = tempPathBuilder ?? _defaultTempPath;

  final AtomicBytesWriter _writer;
  final AtomicFileMover _mover;
  final AtomicTempPathBuilder _tempPathBuilder;

  static int _counter = 0;

  static Future<void> _writeBytes(File file, List<int> bytes) {
    return file.writeAsBytes(bytes, flush: true);
  }

  static Future<File> _rename(File file, String newPath) {
    return file.rename(newPath);
  }

  static String _defaultTempPath(File target) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${target.path}.tmp-$stamp-${_counter++}';
  }

  Future<void> write(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temp = File(_tempPathBuilder(target));
    try {
      await _writer(temp, bytes);
      await _mover(temp, target.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Preserve the original write error.
      }
      rethrow;
    }
  }
}
