import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:naraacare/features/nutrition/data/nutrition_api.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:uuid/uuid.dart';

/// Outcome of saving a meal: saved by the server, or queued while offline
/// (sent by the sync engine with the same client id when back online).
class LogMealResult {
  const new({this.meal, this.summary, this.queued = false});

  final Meal? meal;
  final DailySummary? summary;
  final bool queued;
}

/// A meal waiting in the outbox ("syncing"). Only names and portions are
/// kept: the calories come from the server once it is synced.
class PendingMeal {
  const new({required this.clientEntryId, required this.items});

  final String clientEntryId;
  final List<String> items;
}

/// Nutrition data with the offline rules of doc 03 section 3.1:
/// * a meal saved without a connection goes to the outbox with its
///   client_entry_id and shows as "syncing"; the server answers a replay of
///   the same id with the meal already saved, so nothing is logged twice;
/// * the last daily summary is cached in the encrypted local DB for display.
class NutritionRepository {
  new({
    required this.api,
    required this.db,
    required this.outbox,
    this.clock = const SystemClock(),
  });

  final NutritionApi api;
  final AppDatabase db;
  final Outbox outbox;
  final Clock clock;

  static const _summaryKey = 'nutrition.daily_summary';
  static const _kind = 'meal';

  Future<LogMealResult> logMeal({
    required List<MealItemDraft> items,
    required String mealType,
    required String source,
    DateTime? loggedAt,
  }) async {
    final id = const Uuid().v7();
    final at = loggedAt ?? clock.now();
    final body = api.mealBody(
      clientEntryId: id,
      loggedAt: at,
      mealType: mealType,
      source: source,
      items: items,
    );
    try {
      final response = await api.logMeal(body);
      final summary = response['daily_summary'] as Map<String, dynamic>;
      await _cacheSummary(summary);
      return LogMealResult(
        meal: Meal.fromJson(response['meal'] as Map<String, dynamic>),
        summary: DailySummary.fromJson(summary),
      );
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
                'items': [
                  for (final i in items)
                    '${_qty(i.quantity)} x ${i.portionLabel} ${i.foodName}',
                ],
              }),
              state: 'pending',
              updatedAt: clock.now(),
            ),
          );
      await outbox.enqueue(
        resource: _kind,
        method: 'POST',
        path: 'meals',
        body: {...body}..remove('client_entry_id'),
        clientEntryId: id,
      );
    });
    return const LogMealResult(queued: true);
  }

  Stream<List<PendingMeal>> watchPending() =>
      (db.select(db.localEntries)
            ..where((t) => t.kind.equals(_kind) & t.state.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                PendingMeal(
                  clientEntryId: r.clientEntryId,
                  items:
                      ((jsonDecode(r.payload) as Map<String, dynamic>)['items']
                              as List)
                          .cast<String>(),
                ),
            ],
          );

  /// Today's summary; offline, the last one seen (null if none yet).
  Future<DailySummary?> dailySummary() async {
    try {
      final json = await api.dailySummaryJson();
      await _cacheSummary(json);
      return DailySummary.fromJson(json);
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
      final cached = await (db.select(
        db.cachedStatus,
      )..where((t) => t.key.equals(_summaryKey))).getSingleOrNull();
      if (cached == null) rethrow;
      return DailySummary.fromJson(
        jsonDecode(cached.json) as Map<String, dynamic>,
      );
    }
  }

  Future<void> _cacheSummary(Map<String, dynamic> json) => db
      .into(db.cachedStatus)
      .insertOnConflictUpdate(
        CachedStatusCompanion.insert(
          key: _summaryKey,
          json: jsonEncode(json),
          updatedAt: clock.now(),
        ),
      );

  static String _date(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
