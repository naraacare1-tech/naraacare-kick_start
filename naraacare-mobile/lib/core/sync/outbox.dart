import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:uuid/uuid.dart';

/// Queue of writes made while offline or before the API confirmed them
/// (doc 03 section 3.1). Feature repositories (S08+) call [enqueue] together
/// with writing the optimistic [LocalEntries] row.
class Outbox {
  new(this._db, {this.clock = const SystemClock()});

  final AppDatabase _db;
  final Clock clock;

  /// Queues a create/update/delete. Creates carry `client_entry_id` in the
  /// body, so a replay after a lost response is answered with the original
  /// resource instead of a duplicate. Returns the client entry id.
  Future<String> enqueue({
    required String resource,
    required String method,
    required String path,
    Map<String, Object?>? body,
    int? ifMatchVersion,
    String? clientEntryId,
  }) async {
    final id = clientEntryId ?? const Uuid().v7();
    final payload = body == null
        ? null
        : jsonEncode(
            method == 'POST' ? {...body, 'client_entry_id': id} : body,
          );
    await _db
        .into(_db.outboxItems)
        .insert(
          OutboxItemsCompanion.insert(
            clientEntryId: id,
            resource: resource,
            method: method,
            path: path,
            body: Value(payload),
            ifMatchVersion: Value(ifMatchVersion),
            createdAt: clock.now(),
          ),
        );
    return id;
  }

  /// Items in the order they were made.
  Future<List<OutboxItem>> pending() => (_db.select(
    _db.outboxItems,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<int> count() async => (await pending()).length;

  Future<void> remove(OutboxItem item) =>
      (_db.delete(_db.outboxItems)..where((t) => t.id.equals(item.id))).go();

  Future<void> recordFailure(OutboxItem item, String code) =>
      (_db.update(_db.outboxItems)..where((t) => t.id.equals(item.id))).write(
        OutboxItemsCompanion(
          attempts: Value(item.attempts + 1),
          lastErrorCode: Value(code),
        ),
      );
}
