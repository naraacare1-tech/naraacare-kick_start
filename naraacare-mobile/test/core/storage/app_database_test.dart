import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

const key = 'k8Jt0r4Pz2mYxV9aQ1sB6nW3eL7cU5hD0fG2iK4oR8s=';

void main() {
  test('the database file is encrypted with SQLCipher', () async {
    final dir = Directory.systemTemp.createTempSync('nc_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/naraacare.db');

    final db = AppDatabase.open(file, key);
    await db
        .into(db.cachedStatus)
        .insert(
          CachedStatusCompanion.insert(
            key: 'hydration_today',
            json: '{"level_pct": 81.7}',
            updatedAt: DateTime.utc(2026, 10, 31),
          ),
        );
    await db.close();

    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    expect(String.fromCharCodes(bytes), isNot(contains('level_pct')));

    final withoutKey = sqlite3.open(file.path);
    addTearDown(withoutKey.close);
    expect(
      () => withoutKey.select('SELECT count(*) FROM cached_status'),
      throwsA(isA<SqliteException>()),
    );

    final wrongKey = sqlite3.open(file.path)
      ..execute("PRAGMA key = 'not-the-right-key-not-the-right-key'");
    addTearDown(wrongKey.close);
    expect(
      () => wrongKey.select('SELECT count(*) FROM cached_status'),
      throwsA(isA<SqliteException>()),
    );

    final reopened = AppDatabase.open(file, key);
    addTearDown(reopened.close);
    final rows = await reopened.select(reopened.cachedStatus).get();
    expect(rows.single.json, contains('81.7'));
  });

  test('a malformed key is refused before it reaches SQL', () async {
    final db = AppDatabase.memory("x'; ATTACH DATABASE 'evil' AS e; --");
    addTearDown(db.close);
    expect(
      () => db.select(db.cachedStatus).get(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('wipe removes all local data', () async {
    final db = AppDatabase.memory(key);
    addTearDown(db.close);
    await db
        .into(db.syncState)
        .insert(SyncStateCompanion.insert(key: 'cursor', value: '42'));
    await db.wipe();
    expect(await db.select(db.syncState).get(), isEmpty);
  });
}
