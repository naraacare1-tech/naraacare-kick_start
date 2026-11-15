import 'package:dio/dio.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/features/hydration/data/hydration_models.dart';

/// The hydration and workout endpoints (doc 04 section 2.5). The user is the
/// token's subject: no user id is ever sent.
class HydrationApi {
  const new(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> _map(Future<Object?> call) async =>
      (await call)! as Map<String, dynamic>;

  /// Raw JSON, so the repository can cache it for offline display.
  Future<Map<String, dynamic>> statusJson({String? date}) =>
      _map(api.get('hydration/status', query: {'date': ?date}));

  Future<DrinkCatalogue> drinks() async =>
      DrinkCatalogue.fromJson(await _map(api.get('hydration/drinks')));

  Map<String, Object?> intakeBody({
    required String clientEntryId,
    required DateTime loggedAt,
    required int volumeMl,
    required String source,
    String? drinkCode,
    String? customDrinkId,
  }) => {
    'client_entry_id': clientEntryId,
    'logged_at': loggedAt.toUtc().toIso8601String(),
    'volume_ml': volumeMl,
    'source': source,
    'drink_code': ?drinkCode,
    'custom_drink_id': ?customDrinkId,
  };

  Future<Map<String, dynamic>> logIntake(Map<String, Object?> body) =>
      _map(api.post('hydration/intakes', body: body));

  Future<List<Intake>> intakes(String date) async {
    final body = await _map(
      api.get('hydration/intakes', query: {'date': date}),
    );
    return [
      for (final i in (body['items'] as List).cast<Map<String, dynamic>>())
        Intake.fromJson(i),
    ];
  }

  Future<Map<String, dynamic>> updateIntake(
    String intakeId,
    int version, {
    int? volumeMl,
    String? drinkCode,
    String? customDrinkId,
  }) => _map(
    api.put(
      'hydration/intakes/$intakeId',
      body: {
        'volume_ml': ?volumeMl,
        'drink_code': ?drinkCode,
        'custom_drink_id': ?customDrinkId,
      },
      options: Options(headers: {'If-Match': '$version'}),
    ),
  );

  Future<void> deleteIntake(String intakeId, int version) => api.delete(
    'hydration/intakes/$intakeId',
    options: Options(headers: {'If-Match': '$version'}),
  );

  /// STAR. Stored in Celsius whatever the display unit.
  Future<HydrationStatus> setTemperature(double celsius) async =>
      HydrationStatus.fromJson(
        await _map(
          api.put(
            'hydration/temperature',
            body: {'temperature_c': double.parse(celsius.toStringAsFixed(1))},
          ),
        ),
      );

  Future<DrinkEstimate> estimate(String name) async => DrinkEstimate.fromJson(
    await _map(
      api.post('hydration/custom-drinks/estimate', body: {'name': name}),
    ),
  );

  Future<DrinkOption> saveCustomDrink(
    String name,
    double factor,
    String source,
  ) async => DrinkOption.fromJson(
    await _map(
      api.post(
        'hydration/custom-drinks',
        body: {
          'name': name,
          'hydration_factor': double.parse(factor.toStringAsFixed(3)),
          'source': source,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> logWorkout({
    required String clientEntryId,
    required String workoutType,
    required int durationMin,
    required DateTime performedAt,
  }) => _map(
    api.post(
      'workouts',
      body: {
        'client_entry_id': clientEntryId,
        'workout_type': workoutType,
        'duration_min': durationMin,
        'performed_at': performedAt.toUtc().toIso8601String(),
      },
    ),
  );

  Future<List<Workout>> workouts(String date) async {
    final body = await _map(api.get('workouts', query: {'date': date}));
    return [
      for (final w in (body['items'] as List).cast<Map<String, dynamic>>())
        Workout.fromJson(w),
    ];
  }

  Future<void> deleteWorkout(String workoutId, int version) => api.delete(
    'workouts/$workoutId',
    options: Options(headers: {'If-Match': '$version'}),
  );
}
