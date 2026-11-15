import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/utils/clock.dart';

/// What one pull changed on this device.
class PullResult {
  const new({this.changed = 0, this.conflicts = 0});

  /// Entries added, edited or deleted on another device (or by the server).
  final int changed;

  /// Local edits that lost to a newer server copy (the banner shows).
  final int conflicts;
}

/// Pulls other devices' changes (`GET /sync/changes`, doc 03 section 3.1).
///
/// * The cursor is opaque (the server makes it) and kept in [SyncState]; a
///   new install starts without one and gets the last 7 days.
/// * A local entry the server also changed: if it is still waiting in the
///   outbox, the SERVER copy wins and the entry is flagged `conflict` (the
///   app shows "changed on another device"; the queued write then gets 409
///   and is settled the same way). Synced entries just take the new copy.
/// * Deleted on the server -> removed here.
/// * Pages until `has_more` is false (500 per page), at most 20 pages a run.
class SyncPuller {
  new(this._db, this._api, {this.clock = const SystemClock()});

  final AppDatabase _db;
  final ApiClient _api;
  final Clock clock;

  static const cursorKey = 'changes_cursor';
  static const _kinds = {
    'meals': 'meal',
    'intakes': 'hydration',
    'workouts': 'workout',
    'sleep_entries': 'sleep',
  };

  Future<PullResult> pull() async {
    var changed = 0;
    var conflicts = 0;
    var cursor = await _cursor();
    for (var page = 0; page < 20; page++) {
      final json =
          (await _api.get('sync/changes', query: {'since': ?cursor}))!
              as Map<String, dynamic>;
      final deleted = (json['deleted_ids'] as List).cast<String>();
      await _db.transaction(() async {
        for (final MapEntry(key: field, value: kind) in _kinds.entries) {
          for (final item
              in (json[field] as List).cast<Map<String, dynamic>>()) {
            final result = await _apply(kind, item);
            if (result != null) {
              changed++;
              if (result) conflicts++;
            }
          }
        }
        if (deleted.isNotEmpty) {
          changed += await (_db.delete(
            _db.localEntries,
          )..where((t) => t.serverId.isIn(deleted))).go();
        }
        cursor = json['next_cursor'] as String?;
        if (cursor != null) {
          await _db
              .into(_db.syncState)
              .insertOnConflictUpdate(
                SyncStateCompanion.insert(key: cursorKey, value: cursor!),
              );
        }
      });
      if (json['has_more'] != true) break;
    }
    return PullResult(changed: changed, conflicts: conflicts);
  }

  /// null = not on this device or unchanged; false = updated; true = conflict.
  Future<bool?> _apply(String kind, Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final version = item['version'] as int?;
    final local = await (_db.select(
      _db.localEntries,
    )..where((t) => t.serverId.equals(id))).getSingleOrNull();
    if (local == null || local.version == version) return null;
    final conflict = local.state == 'pending';
    await (_db.update(
      _db.localEntries,
    )..where((t) => t.clientEntryId.equals(local.clientEntryId))).write(
      LocalEntriesCompanion(
        kind: Value(kind),
        payload: Value(jsonEncode(item)),
        version: Value(version),
        state: Value(conflict ? 'conflict' : local.state),
        updatedAt: Value(clock.now()),
      ),
    );
    return conflict;
  }

  Future<String?> _cursor() async => (await (_db.select(
    _db.syncState,
  )..where((t) => t.key.equals(cursorKey))).getSingleOrNull())?.value;
}
