import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/utils/clock.dart';

/// Applies the server's answer to the optimistic local entry (doc 03 3.1):
/// * accepted -> synced, with the server id and version;
/// * 409 VERSION_CONFLICT -> the SERVER copy wins, flagged for the user
///   ("This entry was changed on another device");
/// * 403/404/422 -> rejected and rolled back locally (e.g. outside the
///   last-2 / 7-day edit window, or a STAR-only action), with the code.
class ConflictResolver {
  new(this._db, {this.clock = const SystemClock()});

  final AppDatabase _db;
  final Clock clock;

  /// [response] is the resource itself (`{id, version, ...}`) or wraps it
  /// (`{meal: {meal_id, version, ...}, daily_summary: ...}` from POST /meals).
  Future<void> accepted(String clientEntryId, Object? response) async {
    final outer = response is Map<String, dynamic>
        ? response
        : const <String, dynamic>{};
    final body = outer['meal'] is Map<String, dynamic>
        ? outer['meal'] as Map<String, dynamic>
        : outer;
    await _update(
      clientEntryId,
      LocalEntriesCompanion(
        state: const Value('synced'),
        serverId: Value((body['id'] ?? body['meal_id']) as String?),
        version: Value(body['version'] as int?),
        payload: body.isEmpty ? const Value.absent() : Value(jsonEncode(body)),
        updatedAt: Value(clock.now()),
      ),
    );
  }

  Future<void> serverWins(String clientEntryId, Object? serverCopy) async {
    final copy = serverCopy is Map<String, dynamic> ? serverCopy : null;
    await _update(
      clientEntryId,
      LocalEntriesCompanion(
        state: const Value('conflict'),
        payload: copy == null ? const Value.absent() : Value(jsonEncode(copy)),
        version: copy == null
            ? const Value.absent()
            : Value(copy['version'] as int?),
        updatedAt: Value(clock.now()),
      ),
    );
  }

  Future<void> rejected(String clientEntryId, String code) => _update(
    clientEntryId,
    LocalEntriesCompanion(
      state: const Value('rejected'),
      rejectionCode: Value(code),
      updatedAt: Value(clock.now()),
    ),
  );

  Future<void> _update(String clientEntryId, LocalEntriesCompanion change) =>
      (_db.update(
        _db.localEntries,
      )..where((t) => t.clientEntryId.equals(clientEntryId))).write(change);
}
