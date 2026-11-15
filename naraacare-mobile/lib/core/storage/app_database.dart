import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

part 'app_database.g.dart';

/// Writes waiting to reach the API (doc 03 section 3.1). FIFO by [id].
class OutboxItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// UUIDv7 the server uses to make the create idempotent.
  TextColumn get clientEntryId => text().unique()();

  /// e.g. `hydration_intake`; items of one resource are sent in order.
  TextColumn get resource => text()();
  TextColumn get method => text()();
  TextColumn get path => text()();
  TextColumn get body => text().nullable()();
  IntColumn get ifMatchVersion => integer().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Error code of the last failed attempt (never a message or payload).
  TextColumn get lastErrorCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Entries shown in the UI before and after they sync (own data only).
class LocalEntries extends Table {
  TextColumn get clientEntryId => text()();

  /// hydration | meal | workout | sleep
  TextColumn get kind => text()();

  /// Local calendar date (YYYY-MM-DD) in the user's time zone.
  TextColumn get localDate => text()();
  TextColumn get payload => text()();

  /// pending | synced | conflict | rejected
  TextColumn get state => text()();
  TextColumn get serverId => text().nullable()();
  IntColumn get version => integer().nullable()();
  TextColumn get rejectionCode => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientEntryId};
}

/// Last known server status per screen (avatar fill, targets), for offline.
class CachedStatus extends Table {
  TextColumn get key => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Reference data (GET /reference/bootstrap) with its ETag.
class ReferenceCache extends Table {
  TextColumn get key => text()();
  TextColumn get etag => text()();
  TextColumn get json => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Small key/value state, e.g. the /sync/changes cursor.
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Thrown when the SQLite library is not SQLCipher: the app refuses to keep
/// health data in an unencrypted file (doc 07 SEC-5.9).
class UnencryptedDatabaseError extends StateError {
  new() : super('SQLCipher is not available; refusing to open the database');
}

@DriftDatabase(
  tables: [OutboxItems, LocalEntries, CachedStatus, ReferenceCache, SyncState],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  /// The encrypted on-device database. [key] comes from secure storage.
  factory open(File file, String key) => AppDatabase(
    NativeDatabase.createInBackground(file, setup: keySetup(key)),
  );

  /// Opens on first use: the file location and the key are resolved
  /// asynchronously (path provider, secure storage).
  factory lazy(Future<(File, String)> Function() resolve) => AppDatabase(
    LazyDatabase(() async {
      final (file, key) = await resolve();
      return NativeDatabase.createInBackground(file, setup: keySetup(key));
    }),
  );

  /// An in-memory database for tests (still keyed, so SQLCipher is checked).
  factory memory(String key) =>
      AppDatabase(NativeDatabase.memory(setup: keySetup(key)));

  /// Applies the key before anything else touches the file and verifies that
  /// the library really is SQLCipher.
  static void Function(Database) keySetup(String key) => (db) {
    if (!RegExp(r'^[A-Za-z0-9_=-]{32,}$').hasMatch(key)) {
      throw ArgumentError('database key has an unexpected format');
    }
    final version = db.select('PRAGMA cipher_version');
    if (version.isEmpty || '${version.first.values.first}'.isEmpty) {
      throw UnencryptedDatabaseError();
    }
    // The key is base64url (validated above), so quoting is safe.
    db
      ..execute("PRAGMA key = '$key'")
      ..execute('PRAGMA foreign_keys = ON');
  };

  @override
  int get schemaVersion => 1;

  /// Removes everything of the signed-in user (logout, account deletion).
  Future<void> wipe() => transaction(() async {
    for (final table in allTables) {
      await delete(table).go();
    }
  });
}
