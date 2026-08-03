import 'in_memory_server.dart';
import 'mutation.dart';

class DeviceLedger {
  DeviceLedger({required this.deviceId});

  final String deviceId;
  final List<PendingMutation> pending = [];
  final Map<String, Map<String, Object?>> entities = {};
  final Map<String, Map<String, Object?>> conflicts = {};
  int cursor = 0;

  void enqueue(PendingMutation mutation) {
    pending.add(mutation);
    // Local-first optimistic apply
    entities[mutation.entityId] = {
      'version': mutation.baseVersion + 1,
      'payload': mutation.payload,
      'pending': true,
    };
  }

  void push(InMemorySyncServer server, String bookId) {
    if (pending.isEmpty) return;
    final batch = List<PendingMutation>.from(pending);
    final receipts = server.push(
      bookId: bookId,
      deviceId: deviceId,
      mutations: batch,
    );
    for (final receipt in receipts) {
      final idx = pending.indexWhere((m) => m.mutationId == receipt.mutationId);
      if (idx < 0) continue;
      final mutation = pending.removeAt(idx);
      if (receipt.status == 'applied') {
        entities[mutation.entityId] = {
          'version': receipt.entityVersion,
          'payload': mutation.payload,
          'pending': false,
        };
      } else if (receipt.resultCode == 'LEDGER_VERSION_CONFLICT') {
        conflicts[mutation.entityId] = {
          'local': mutation.payload,
          'reason': receipt.resultCode,
          'remoteVersion': receipt.entityVersion,
        };
      }
    }
  }

  void pull(InMemorySyncServer server, String bookId) {
    final page = server.pull(bookId: bookId, cursor: cursor);
    for (final change in page.changes) {
      entities[change.entityId] = {
        'version': change.version,
        'payload': change.payload,
        'pending': false,
      };
    }
    cursor = page.nextCursor;
  }
}
