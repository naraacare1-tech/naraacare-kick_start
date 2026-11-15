import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:uuid/uuid.dart';

/// A night waking inside an entry.
class NightWaking {
  const new({required this.wokeAt, required this.backAsleepAt});

  factory fromJson(Map<String, dynamic> json) => NightWaking(
    wokeAt: DateTime.parse(json['woke_at'] as String),
    backAsleepAt: DateTime.parse(json['back_asleep_at'] as String),
  );

  final DateTime wokeAt;
  final DateTime backAsleepAt;

  Map<String, Object?> toJson() => {
    'woke_at': wokeAt.toUtc().toIso8601String(),
    'back_asleep_at': backAsleepAt.toUtc().toIso8601String(),
  };
}

class SleepEntry {
  const new({
    required this.entryId,
    required this.sleepStart,
    required this.wakeTime,
    required this.countedMin,
    required this.version,
    required this.editable,
    required this.wakings,
  });

  factory fromJson(Map<String, dynamic> json) => SleepEntry(
    entryId: json['entry_id'] as String,
    sleepStart: DateTime.parse(json['sleep_start'] as String),
    wakeTime: DateTime.parse(json['wake_time'] as String),
    countedMin: (json['counted_min'] as num).toInt(),
    version: (json['version'] as num).toInt(),
    editable: json['editable'] as bool,
    wakings: [
      for (final w in (json['wakings'] as List).cast<Map<String, dynamic>>())
        NightWaking.fromJson(w),
    ],
  );

  final String entryId;
  final DateTime sleepStart;
  final DateTime wakeTime;
  final int countedMin;
  final int version;
  final bool editable;
  final List<NightWaking> wakings;
}

enum SleepLabel { none, good, fair, low }

/// GET /sleep/summary: everything comes from the server (doc 06 section 4).
class SleepSummary {
  const new({
    required this.date,
    required this.countedMin,
    required this.goalMin,
    required this.scorePct,
    required this.label,
    required this.onsetBufferMin,
    required this.wakeBufferMin,
    required this.wakingBufferMin,
    required this.entries,
  });

  factory fromJson(Map<String, dynamic> json) {
    final buffers = json['buffers'] as Map<String, dynamic>;
    return SleepSummary(
      date: json['date'] as String,
      countedMin: (json['counted_min'] as num).toInt(),
      goalMin: (json['goal_min'] as num).toInt(),
      scorePct: (json['score_pct'] as num).toInt(),
      label: switch (json['label']) {
        'good' => SleepLabel.good,
        'fair' => SleepLabel.fair,
        'low' => SleepLabel.low,
        _ => SleepLabel.none,
      },
      onsetBufferMin: (buffers['onset_min'] as num).toInt(),
      wakeBufferMin: (buffers['wake_min'] as num).toInt(),
      wakingBufferMin: (buffers['waking_min'] as num).toInt(),
      entries: [
        for (final e in (json['entries'] as List).cast<Map<String, dynamic>>())
          SleepEntry.fromJson(e),
      ],
    );
  }

  final String date;
  final int countedMin;
  final int goalMin;
  final int scorePct;
  final SleepLabel label;
  final int onsetBufferMin;
  final int wakeBufferMin;
  final int wakingBufferMin;
  final List<SleepEntry> entries;
}

/// Sleep endpoints (doc 04 section 2.6). STAR only (the server answers 403
/// UPGRADE_REQUIRED otherwise).
class SleepApi {
  const new(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> _map(Future<Object?> call) async =>
      (await call)! as Map<String, dynamic>;

  Future<Map<String, dynamic>> summaryJson({String? date}) =>
      _map(api.get('sleep/summary', query: {'date': ?date}));

  Map<String, Object?> entryBody({
    required DateTime sleepStart,
    required DateTime wakeTime,
    required List<NightWaking> wakings,
  }) => {
    'sleep_start': sleepStart.toUtc().toIso8601String(),
    'wake_time': wakeTime.toUtc().toIso8601String(),
    'wakings': [for (final w in wakings) w.toJson()],
  };

  Future<Map<String, dynamic>> logEntry(Map<String, Object?> body) =>
      _map(api.post('sleep/entries', body: body));

  Future<Map<String, dynamic>> updateEntry(
    String entryId,
    int version,
    Map<String, Object?> body,
  ) => _map(
    api.put(
      'sleep/entries/$entryId',
      body: body,
      options: Options(headers: {'If-Match': '$version'}),
    ),
  );

  Future<void> deleteEntry(String entryId, int version) => api.delete(
    'sleep/entries/$entryId',
    options: Options(headers: {'If-Match': '$version'}),
  );

  Future<void> setGoal(int goalMin) =>
      api.put('me/sleep-goal', body: {'goal_min': goalMin});
}

/// Offline rules as meals and drinks (doc 03 section 3.1): an entry saved
/// without a connection goes to the outbox with its client id; the last
/// summary is cached in the encrypted local DB.
class SleepRepository {
  new({
    required this.api,
    required this.db,
    required this.outbox,
    this.clock = const SystemClock(),
  });

  final SleepApi api;
  final AppDatabase db;
  final Outbox outbox;
  final Clock clock;

  static const _summaryKey = 'sleep.summary';

  /// True when queued offline.
  Future<bool> logEntry({
    required DateTime sleepStart,
    required DateTime wakeTime,
    required List<NightWaking> wakings,
  }) async {
    final id = const Uuid().v7();
    final body = {
      'client_entry_id': id,
      ...api.entryBody(
        sleepStart: sleepStart,
        wakeTime: wakeTime,
        wakings: wakings,
      ),
    };
    try {
      final response = await api.logEntry(body);
      await _cache(response['summary'] as Map<String, dynamic>);
      return false;
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
    }
    await outbox.enqueue(
      resource: 'sleep_entry',
      method: 'POST',
      path: 'sleep/entries',
      body: {...body}..remove('client_entry_id'),
      clientEntryId: id,
    );
    return true;
  }

  Future<SleepSummary> summary() async {
    try {
      final json = await api.summaryJson();
      await _cache(json);
      return SleepSummary.fromJson(json);
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
      final cached = await (db.select(
        db.cachedStatus,
      )..where((t) => t.key.equals(_summaryKey))).getSingleOrNull();
      if (cached == null) rethrow;
      return SleepSummary.fromJson(
        jsonDecode(cached.json) as Map<String, dynamic>,
      );
    }
  }

  Future<void> _cache(Map<String, dynamic> json) => db
      .into(db.cachedStatus)
      .insertOnConflictUpdate(
        CachedStatusCompanion.insert(
          key: _summaryKey,
          json: jsonEncode(json),
          updatedAt: clock.now(),
        ),
      );
}
