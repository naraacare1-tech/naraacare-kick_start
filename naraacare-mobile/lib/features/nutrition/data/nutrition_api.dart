import 'package:dio/dio.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';

/// The nutrition endpoints (doc 04 section 2.4). The user is always the
/// token's subject: no user id is ever sent.
class NutritionApi {
  const new(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> _map(Future<Object?> call) async =>
      (await call)! as Map<String, dynamic>;

  Future<List<FoodSearchResult>> search(String query) async {
    final body = await _map(
      api.get('foods/search', query: {'q': query, 'limit': 25}),
    );
    return (body['results'] as List)
        .cast<Map<String, dynamic>>()
        .map(FoodSearchResult.fromJson)
        .toList();
  }

  Future<FoodDetail> food(String foodId) async =>
      FoodDetail.fromJson(await _map(api.get('foods/$foodId')));

  Future<BarcodeResult> barcode(String code) async =>
      BarcodeResult.fromJson(await _map(api.get('foods/barcode/$code')));

  Future<VoiceParse> parseVoice(String transcript, String locale) async =>
      VoiceParse.fromJson(
        await _map(
          api.post(
            'nutrition/voice/parse',
            body: {'transcript': transcript, 'locale': locale},
          ),
        ),
      );

  /// Raw JSON, so the repository can cache it for offline display.
  Future<Map<String, dynamic>> dailySummaryJson({String? date}) =>
      _map(api.get('nutrition/daily-summary', query: {'date': ?date}));

  Map<String, Object?> mealBody({
    required String clientEntryId,
    required DateTime loggedAt,
    required String mealType,
    required String source,
    required List<MealItemDraft> items,
  }) => {
    'client_entry_id': clientEntryId,
    'logged_at': loggedAt.toUtc().toIso8601String(),
    'meal_type': mealType,
    'source': source,
    'items': [for (final i in items) i.toJson()],
  };

  /// Server-side totals for the current list; nothing is saved.
  Future<MealPreview> preview(Map<String, Object?> mealBody) async =>
      MealPreview.fromJson(
        await _map(api.post('meals?dry_run=true', body: mealBody)),
      );

  Future<Map<String, dynamic>> logMeal(Map<String, Object?> mealBody) =>
      _map(api.post('meals', body: mealBody));

  Future<Map<String, dynamic>> updateMeal(
    String mealId,
    int version, {
    String? mealType,
    List<MealItemDraft>? items,
  }) => _map(
    api.put(
      'meals/$mealId',
      body: {
        'meal_type': ?mealType,
        if (items != null) 'items': [for (final i in items) i.toJson()],
      },
      options: Options(headers: {'If-Match': '$version'}),
    ),
  );

  Future<void> deleteMeal(String mealId, int version) => api.delete(
    'meals/$mealId',
    options: Options(headers: {'If-Match': '$version'}),
  );

  Future<RecentMeals> recent() async =>
      RecentMeals.fromJson(await _map(api.get('meals/recent')));

  Future<MealBreakdown> breakdown(String mealId) async =>
      MealBreakdown.fromJson(await _map(api.get('meals/$mealId/breakdown')));

  Future<List<SavedMeal>> savedMeals() async {
    final body = await _map(api.get('saved-meals'));
    return (body['saved_meals'] as List)
        .cast<Map<String, dynamic>>()
        .map(SavedMeal.fromJson)
        .toList();
  }

  Future<void> saveMealTemplate(String name, List<MealItemDraft> items) =>
      api.post(
        'saved-meals',
        body: {
          'name': name,
          'items': [for (final i in items) i.toJson()],
        },
      );

  Future<void> deleteSavedMeal(String id) => api.delete('saved-meals/$id');
}
