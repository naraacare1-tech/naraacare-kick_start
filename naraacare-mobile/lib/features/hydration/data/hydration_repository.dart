import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:naraacare/features/hydration/data/hydration_api.dart';
import 'package:naraacare/features/hydration/data/hydration_models.dart';
import 'package:uuid/uuid.dart';

/// Outcome of logging a drink: saved (with the new status) or queued offline.
class LogIntakeResult {
  const new({this.status, this.queued = false});

  final HydrationStatus? status;
  final bool queued;
}

/// Hydration data with the offline rules of doc 03 section 3.1 (as meals):
/// a drink logged without a connection goes to the outbox with its
/// client_entry_id and its effective mL (volume x factor, both from the
/// server's drink list) is added to the last status for display only. The
/// last status is cached in the encrypted local DB.
class HydrationRepository {
  new({
    required this.api,
    required this.db,
    required this.outbox,
    this.clock = const SystemClock(),
  });

  final HydrationApi api;
  final AppDatabase db;
  final Outbox outbox;
  final Clock clock;

  static const _statusKey = 'hydration.status';
  static const _kind = 'intake';

  Future<LogIntakeResult> logIntake({
    required DrinkOption drink,
    required int volumeMl,
    required String source,
  }) async {
    final id = const Uuid().v7();
    final at = clock.now();
    final body = api.intakeBody(
      clientEntryId: id,
      loggedAt: at,
      volumeMl: volumeMl,
      source: source,
      drinkCode: drink.drinkCode,
      customDrinkId: drink.customDrinkId,
    );
    try {
      final response = await api.logIntake(body);
      final status = response['status'] as Map<String, dynamic>;
      await _cache(status);
      return LogIntakeResult(status: HydrationStatus.fromJson(status));
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
    }
    await db.transaction(() async {
      await db
          .into(db.localEntries)
          .insert(
            LocalEntriesCompanion.insert(
              clientEntryId: id,
              kind: _kind,
              localDate: _date(at),
              payload: jsonEncode({
                'effective_ml': (volumeMl * drink.hydrationFactor).round(),
              }),
              state: 'pending',
              updatedAt: clock.now(),
            ),
          );
      await outbox.enqueue(
        resource: _kind,
        method: 'POST',
        path: 'hydration/intakes',
        body: {...body}..remove('client_entry_id'),
        clientEntryId: id,
      );
    });
    return const LogIntakeResult(queued: true);
  }

  /// Effective mL of today's drinks still waiting in the outbox.
  Stream<int> watchPendingMl() =>
      (db.select(db.localEntries)..where(
            (t) =>
                t.kind.equals(_kind) &
                t.state.equals('pending') &
                t.localDate.equals(_date(clock.now())),
          ))
          .watch()
          .map(
            (rows) => rows.fold<int>(
              0,
              (sum, r) =>
                  sum +
                  ((jsonDecode(r.payload)
                              as Map<String, dynamic>)['effective_ml']
                          as num)
                      .round(),
            ),
          );

  /// Today's status; offline, the last one seen (rethrows if none yet).
  Future<HydrationStatus> status() async {
    try {
      final json = await api.statusJson();
      await _cache(json);
      return HydrationStatus.fromJson(json);
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
      final cached = await (db.select(
        db.cachedStatus,
      )..where((t) => t.key.equals(_statusKey))).getSingleOrNull();
      if (cached == null) rethrow;
      return HydrationStatus.fromJson(
        jsonDecode(cached.json) as Map<String, dynamic>,
      );
    }
  }

  Future<void> cache(Map<String, dynamic> json) => _cache(json);

  Future<void> _cache(Map<String, dynamic> json) => db
      .into(db.cachedStatus)
      .insertOnConflictUpdate(
        CachedStatusCompanion.insert(
          key: _statusKey,
          json: jsonEncode(json),
          updatedAt: clock.now(),
        ),
      );

  static String _date(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  static String today(Clock clock) => _date(clock.now());
}
