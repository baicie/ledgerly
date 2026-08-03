import 'package:drift/drift.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get currencyCode => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get currencyCode => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get description => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TransactionEntries extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get accountId => text()();
  TextColumn get amountMinor => text()();
  TextColumn get currencyCode => text()();
  IntColumn get entryIndex => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class PendingMutations extends Table {
  TextColumn get mutationId => text()();
  TextColumn get bookId => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  IntColumn get baseVersion => integer()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {mutationId};
}

class SyncStates extends Table {
  TextColumn get bookId => text()();
  TextColumn get deviceId => text()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  TextColumn get accessToken => text().nullable()();
  TextColumn get refreshToken => text().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

class SyncConflicts extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get entityId => text()();
  TextColumn get reason => text()();
  TextColumn get localPayloadJson => text()();
  IntColumn get remoteVersion => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
