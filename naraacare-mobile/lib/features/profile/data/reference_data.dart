import 'dart:convert';

import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/utils/clock.dart';

/// A labelled reference code (activity level, goal, condition, body type).
typedef RefItem = ({String code, String label});

/// The public reference payload (GET /reference/bootstrap): labels for the
/// codes the onboarding and settings screens show. Display data only.
class ReferenceData {
  const new(this.json);

  final Map<String, dynamic> json;

  List<RefItem> _items(String key, {String labelKey = 'label'}) => [
    for (final item
        in (json[key] as List? ?? const []).cast<Map<String, dynamic>>())
      (
        code: item['code'] as String,
        label: (item[labelKey] ?? item['label']) as String,
      ),
  ];

  List<RefItem> get activityLevels =>
      _items('activity_levels', labelKey: 'onboarding_label');
  List<RefItem> get bodyTypes => _items('body_types');
  List<RefItem> get weightGoals => _items('weight_goals');
  List<RefItem> get medicalConditions => _items('medical_conditions');

  String label(List<RefItem> items, String? code) {
    for (final item in items) {
      if (item.code == code) return item.label;
    }
    return code ?? '';
  }
}

/// Fetches the reference payload once an hour (it is the same for every
/// user) and keeps the last copy in the encrypted local DB for offline use.
class ReferenceRepository {
  new({required this.api, required this.db, this.clock = const SystemClock()});

  final ApiClient api;
  final AppDatabase db;
  final Clock clock;

  static const _key = 'bootstrap';
  static const maxAge = Duration(hours: 1);

  Future<ReferenceData> load() async {
    final cached = await (db.select(
      db.referenceCache,
    )..where((t) => t.key.equals(_key))).getSingleOrNull();
    final fresh =
        cached != null && clock.now().difference(cached.fetchedAt) < maxAge;
    if (fresh) return ReferenceData(_decode(cached.json));
    try {
      final body =
          (await api.get('reference/bootstrap'))! as Map<String, dynamic>;
      await db
          .into(db.referenceCache)
          .insertOnConflictUpdate(
            ReferenceCacheCompanion.insert(
              key: _key,
              etag: '',
              json: jsonEncode(body),
              fetchedAt: clock.now(),
            ),
          );
      return ReferenceData(body);
    } on ApiError {
      if (cached != null) return ReferenceData(_decode(cached.json));
      rethrow;
    }
  }

  static Map<String, dynamic> _decode(String json) =>
      jsonDecode(json) as Map<String, dynamic>;
}
