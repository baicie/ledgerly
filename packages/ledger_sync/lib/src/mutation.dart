class PendingMutation {
  PendingMutation({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.baseVersion,
    required this.payload,
  });

  final String mutationId;
  final String entityType;
  final String entityId;
  final String operation;
  final int baseVersion;
  final Map<String, Object?> payload;
}

class MutationReceipt {
  MutationReceipt({
    required this.mutationId,
    required this.status,
    required this.resultCode,
    this.entityVersion,
  });

  final String mutationId;
  final String status;
  final String resultCode;
  final int? entityVersion;
}

class SyncChange {
  SyncChange({
    required this.sequence,
    required this.commitId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.version,
    required this.payload,
  });

  final int sequence;
  final String commitId;
  final String entityType;
  final String entityId;
  final String operation;
  final int version;
  final Map<String, Object?> payload;
}
