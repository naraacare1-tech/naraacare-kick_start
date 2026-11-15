/// Hydration data as the server returns it (doc 04 section 2.5). The app
/// does no hydration maths: levels, goals and states come from the server;
/// only a just-queued drink is added optimistically (doc 06 section 10).
library;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.round() ?? 0;

enum HydrationBand { well, drinkSoon, low, critical }

enum HydrationState {
  empty,
  inProgress,
  goalCompleted,
  aboveGoal,
  dayEndingSoon,
}

HydrationBand _band(String code) => switch (code) {
  'well' => HydrationBand.well,
  'drink_soon' => HydrationBand.drinkSoon,
  'low' => HydrationBand.low,
  _ => HydrationBand.critical,
};

HydrationState _state(String code) => switch (code) {
  'in_progress' => HydrationState.inProgress,
  'goal_completed' => HydrationState.goalCompleted,
  'above_goal' => HydrationState.aboveGoal,
  'day_ending_soon' => HydrationState.dayEndingSoon,
  _ => HydrationState.empty,
};

/// GET /hydration/status. [pendingMl] is the effective mL of drinks still in
/// the outbox (optimistic display only).
class HydrationStatus {
  const new({
    required this.date,
    required this.levelPct,
    required this.band,
    required this.balanceMl,
    required this.tankMl,
    required this.dailyGoalMl,
    required this.effectiveIntakeMl,
    required this.consumedPct,
    required this.leftToDrinkMl,
    required this.state,
    required this.overhydrationCaution,
    required this.temperatureC,
    required this.temperatureUnit,
    required this.temperatureStale,
    required this.foodWaterMl,
    required this.workoutSweatMl,
    required this.drainMlPerHour,
    required this.breakdown,
    required this.advanced,
    this.temperatureSetAt,
    this.pendingMl = 0,
  });

  factory fromJson(Map<String, dynamic> json) {
    final temp = json['temperature'] as Map<String, dynamic>;
    return HydrationStatus(
      date: json['date'] as String,
      levelPct: _d(json['level_pct']),
      band: _band(json['band'] as String),
      balanceMl: _i(json['balance_ml']),
      tankMl: _i(json['tank_ml']),
      dailyGoalMl: _i(json['daily_goal_ml']),
      effectiveIntakeMl: _i(json['effective_intake_ml']),
      consumedPct: _d(json['consumed_pct']),
      leftToDrinkMl: _i(json['left_to_drink_ml']),
      state: _state(json['state'] as String),
      overhydrationCaution: json['overhydration_caution'] as bool,
      temperatureC: _d(temp['c']),
      temperatureUnit: temp['unit'] as String? ?? 'c',
      temperatureSetAt: temp['set_at'] == null
          ? null
          : DateTime.parse(temp['set_at'] as String),
      temperatureStale: temp['stale'] as bool,
      foodWaterMl: _i(json['food_water_ml']),
      workoutSweatMl: _i(json['workout_sweat_ml']),
      drainMlPerHour: _d(json['drain_ml_per_hour']),
      breakdown: {
        for (final e in (json['breakdown'] as Map<String, dynamic>).entries)
          e.key: _i(e.value),
      },
      advanced: json['advanced'] as bool? ?? false,
    );
  }

  final String date;
  final double levelPct;
  final HydrationBand band;
  final int balanceMl;
  final int tankMl;
  final int dailyGoalMl;
  final int effectiveIntakeMl;
  final double consumedPct;
  final int leftToDrinkMl;
  final HydrationState state;
  final bool overhydrationCaution;
  final double temperatureC;
  final String temperatureUnit;
  final DateTime? temperatureSetAt;
  final bool temperatureStale;
  final int foodWaterMl;
  final int workoutSweatMl;
  final double drainMlPerHour;
  final Map<String, int> breakdown;
  final bool advanced;
  final int pendingMl;

  /// Intake shown on the card: server value plus queued drinks.
  int get shownIntakeMl => effectiveIntakeMl + pendingMl;

  HydrationStatus withPending(int ml) => HydrationStatus(
    date: date,
    levelPct: levelPct,
    band: band,
    balanceMl: balanceMl,
    tankMl: tankMl,
    dailyGoalMl: dailyGoalMl,
    effectiveIntakeMl: effectiveIntakeMl,
    consumedPct: consumedPct,
    leftToDrinkMl: leftToDrinkMl,
    state: state,
    overhydrationCaution: overhydrationCaution,
    temperatureC: temperatureC,
    temperatureUnit: temperatureUnit,
    temperatureSetAt: temperatureSetAt,
    temperatureStale: temperatureStale,
    foodWaterMl: foodWaterMl,
    workoutSweatMl: workoutSweatMl,
    drainMlPerHour: drainMlPerHour,
    breakdown: breakdown,
    advanced: advanced,
    pendingMl: ml,
  );
}

/// A standard drink (`drinkCode`) or one of the user's custom drinks
/// (`customDrinkId`). [locked] = needs STAR for this user.
class DrinkOption {
  const new({
    required this.label,
    required this.hydrationFactor,
    required this.locked,
    this.drinkCode,
    this.customDrinkId,
  });

  factory fromJson(Map<String, dynamic> json) => DrinkOption(
    label: json['label'] as String,
    hydrationFactor: _d(json['hydration_factor']),
    locked: json['locked'] as bool,
    drinkCode: json['drink_code'] as String?,
    customDrinkId: json['custom_drink_id'] as String?,
  );

  final String label;
  final double hydrationFactor;
  final bool locked;
  final String? drinkCode;
  final String? customDrinkId;

  bool get isWater => drinkCode == 'water';
}

class DrinkCatalogue {
  const new({
    required this.drinks,
    required this.customDrinks,
    required this.presetsMl,
    required this.quickAddMl,
  });

  factory fromJson(Map<String, dynamic> json) => DrinkCatalogue(
    drinks: [
      for (final d in (json['drinks'] as List).cast<Map<String, dynamic>>())
        DrinkOption.fromJson(d),
    ],
    customDrinks: [
      for (final d
          in (json['custom_drinks'] as List).cast<Map<String, dynamic>>())
        DrinkOption.fromJson(d),
    ],
    presetsMl: (json['presets_ml'] as List).cast<int>(),
    quickAddMl: _i(json['quick_add_ml']),
  );

  final List<DrinkOption> drinks;
  final List<DrinkOption> customDrinks;
  final List<int> presetsMl;
  final int quickAddMl;
}

/// A logged drink (Recent Updates, edit last 2).
class Intake {
  const new({
    required this.intakeId,
    required this.loggedAt,
    required this.label,
    required this.volumeMl,
    required this.effectiveMl,
    required this.source,
    required this.version,
    required this.editable,
    this.drinkCode,
    this.customDrinkId,
  });

  factory fromJson(Map<String, dynamic> json) => Intake(
    intakeId: json['intake_id'] as String,
    loggedAt: DateTime.parse(json['logged_at'] as String),
    label: json['label'] as String,
    volumeMl: _i(json['volume_ml']),
    effectiveMl: _d(json['effective_ml']),
    source: json['source'] as String,
    version: _i(json['version']),
    editable: json['editable'] as bool,
    drinkCode: json['drink_code'] as String?,
    customDrinkId: json['custom_drink_id'] as String?,
  );

  final String intakeId;
  final DateTime loggedAt;
  final String label;
  final int volumeMl;
  final double effectiveMl;
  final String source;
  final int version;
  final bool editable;
  final String? drinkCode;
  final String? customDrinkId;

  bool get isSwipeDown => volumeMl < 0;
}

class Workout {
  const new({
    required this.workoutId,
    required this.performedAt,
    required this.workoutType,
    required this.label,
    required this.durationMin,
    required this.sweatMl,
    required this.kcal,
    required this.version,
    required this.editable,
  });

  factory fromJson(Map<String, dynamic> json) => Workout(
    workoutId: json['workout_id'] as String,
    performedAt: DateTime.parse(json['performed_at'] as String),
    workoutType: json['workout_type'] as String,
    label: json['label'] as String,
    durationMin: _i(json['duration_min']),
    sweatMl: _d(json['sweat_ml']),
    kcal: _i(json['kcal']),
    version: _i(json['version']),
    editable: json['editable'] as bool,
  );

  final String workoutId;
  final DateTime performedAt;
  final String workoutType;
  final String label;
  final int durationMin;
  final double sweatMl;
  final int kcal;
  final int version;
  final bool editable;
}

/// POST /hydration/custom-drinks/estimate: the user confirms before saving.
class DrinkEstimate {
  const new({
    required this.hydrationFactor,
    required this.source,
    required this.explanationCode,
  });

  factory fromJson(Map<String, dynamic> json) => DrinkEstimate(
    hydrationFactor: _d(json['hydration_factor']),
    source: json['source'] as String,
    explanationCode: json['explanation_code'] as String,
  );

  final double hydrationFactor;
  final String source;
  final String explanationCode;
}

const workoutTypes = [
  'walking',
  'gym',
  'cycling',
  'swimming',
  'running',
  'trekking',
];
