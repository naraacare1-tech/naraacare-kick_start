import 'package:naraacare/core/network/api_client.dart';

/// Metric profile as the API returns it (`ProfileOut`, doc 04 section 2.2).
class Profile {
  const new({
    this.biologicalSex,
    this.avatarCode,
    this.fullName,
    this.ageYears,
    this.heightCm,
    this.weightKg,
    this.targetWeightKg,
    this.weightGoal,
    this.activityLevel,
    this.bodyType,
    this.conditionCodes = const [],
  });

  factory fromJson(Map<String, dynamic> json) => Profile(
    biologicalSex: json['biological_sex'] as String?,
    avatarCode: json['avatar_code'] as String?,
    fullName: json['full_name'] as String?,
    ageYears: json['age_years'] as int?,
    heightCm: _decimal(json['height_cm']),
    weightKg: _decimal(json['weight_kg']),
    targetWeightKg: _decimal(json['target_weight_kg']),
    weightGoal: json['weight_goal'] as String?,
    activityLevel: json['activity_level'] as String?,
    bodyType: json['body_type'] as String?,
    conditionCodes:
        (json['medical_condition_codes'] as List?)?.cast<String>() ?? const [],
  );

  final String? biologicalSex;
  final String? avatarCode;
  final String? fullName;
  final int? ageYears;
  final double? heightCm;
  final double? weightKg;
  final double? targetWeightKg;
  final String? weightGoal;
  final String? activityLevel;
  final String? bodyType;
  final List<String> conditionCodes;
}

/// Decimals arrive as JSON strings (Pydantic Decimal) or numbers.
double? _decimal(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// Decimal on the wire: a string with fixed places, as the API expects.
String wireDecimal(double value, int places) => value.toStringAsFixed(places);

class Me {
  const new({
    required this.email,
    required this.tier,
    required this.username,
    required this.onboardingStep,
    required this.onboardingCompleted,
    required this.profile,
    required this.settings,
    this.userId = '',
    this.counts = const ProfileCounts(),
    this.memberSince,
  });

  factory fromJson(Map<String, dynamic> json) {
    final onboarding = json['onboarding'] as Map<String, dynamic>;
    return Me(
      userId: (json['user_id'] as String?) ?? '',
      email: json['email'] as String,
      tier: json['tier'] as String,
      username: json['username'] as String?,
      onboardingStep: onboarding['current_step'] as int,
      onboardingCompleted: onboarding['completed'] as bool,
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      settings: json['settings'] as Map<String, dynamic>,
      counts: ProfileCounts.fromJson(
        (json['counts'] as Map<String, dynamic>?) ?? const {},
      ),
      memberSince: json['member_since'] == null
          ? null
          : DateTime.parse(json['member_since'] as String),
    );
  }

  /// The caller's id (to tell "you" apart in circle lists).
  final String userId;
  final String email;
  final String tier;
  final String? username;
  final int onboardingStep;
  final bool onboardingCompleted;
  final Profile profile;

  /// Raw settings (`SettingsOut`): PUT /me/settings needs every field back.
  final Map<String, dynamic> settings;

  /// Profile header counts (S14).
  final ProfileCounts counts;

  /// The local day the account was created (the first report month).
  final DateTime? memberSince;

  bool get isStar => tier == 'star';

  bool get usesFeetInches => settings['height_unit'] == 'ft_in';
  bool get usesPounds => settings['weight_unit'] == 'lb';
}

/// Connections, circles and the streak shown in the Profile header.
class ProfileCounts {
  const new({
    this.connections = 0,
    this.circles = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
  });

  factory fromJson(Map<String, dynamic> json) => ProfileCounts(
    connections: (json['connections'] as int?) ?? 0,
    circles: (json['circles'] as int?) ?? 0,
    currentStreak: (json['current_streak'] as int?) ?? 0,
    longestStreak: (json['longest_streak'] as int?) ?? 0,
  );

  final int connections;
  final int circles;
  final int currentStreak;
  final int longestStreak;
}

typedef GoalOptions = ({
  double bmi,
  String category,
  List<String> allowedGoals,
  int healthyMinKg,
  int healthyMaxKg,
});

typedef Targets = ({int kcal, int waterMl, double bmi, String bmiCategory});

/// Profile, onboarding, username and consent endpoints (doc 04 sections 2.2
/// and 2.13). The user is always the token's subject: no ids are sent.
class ProfileApi {
  const new(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> _map(Future<Object?> call) async =>
      (await call)! as Map<String, dynamic>;

  Future<Me> me() async => Me.fromJson(await _map(api.get('me')));

  /// Resume point: the last saved step (0-6) and what was saved so far.
  Future<({int step, bool completed, Profile soFar})> onboarding() async {
    final body = await _map(api.get('me/onboarding'));
    return (
      step: body['current_step'] as int,
      completed: body['completed'] as bool,
      soFar: Profile.fromJson(body['data_so_far'] as Map<String, dynamic>),
    );
  }

  /// Saves one step's fields (only that step's fields are accepted).
  Future<int> saveStep(int step, Map<String, Object?> fields) async {
    final body = await _map(api.put('me/onboarding/steps/$step', body: fields));
    return body['current_step'] as int;
  }

  Future<GoalOptions> goalOptions({double? weightKg, double? heightCm}) async {
    final body = await _map(
      api.get(
        'me/goal-options',
        query: {
          if (weightKg != null) 'weight_kg': wireDecimal(weightKg, 2),
          if (heightCm != null) 'height_cm': wireDecimal(heightCm, 1),
        },
      ),
    );
    final range = (body['healthy_weight_range_kg'] as List).cast<int>();
    return (
      bmi: _decimal(body['bmi'])!,
      category: body['category'] as String,
      allowedGoals: (body['allowed_goals'] as List).cast<String>(),
      healthyMinKg: range[0],
      healthyMaxKg: range[1],
    );
  }

  /// Result page numbers (no local maths, S07 acceptance criterion).
  Future<Targets> preview() async {
    final body = await _map(api.post('calculations/preview'));
    final targets = body['targets'] as Map<String, dynamic>;
    return (
      kcal: targets['kcal'] as int,
      waterMl: body['water_need_ml'] as int,
      bmi: _decimal(body['bmi'])!,
      bmiCategory: body['bmi_category'] as String,
    );
  }

  /// Completes onboarding with the consent decisions (SEC-7.1).
  Future<void> complete(List<Map<String, Object?>> consents) =>
      api.post('me/onboarding/complete', body: {'consents': consents});

  Future<Me> patchProfile(Map<String, Object?> fields) async {
    final body = await _map(api.patch('me/profile', body: fields));
    return Me.fromJson(body['me'] as Map<String, dynamic>);
  }

  Future<void> putSettings(Map<String, Object?> settings) =>
      api.put('me/settings', body: settings);

  /// Today's nutrition targets (GET /me/targets/today) for the info sheet.
  Future<({int kcal, int carbsG, int fatG, int proteinG})>
  targetsToday() async {
    final body = await _map(api.get('me/targets/today'));
    final n = body['nutrition'] as Map<String, dynamic>;
    return (
      kcal: n['kcal'] as int,
      carbsG: n['carbs_g'] as int,
      fatG: n['fat_g'] as int,
      proteinG: n['protein_g'] as int,
    );
  }

  Future<bool> usernameAvailable(String username) async {
    final body = await _map(
      api.get('usernames/availability', query: {'username': username}),
    );
    return body['available'] as bool;
  }

  Future<void> setUsername(String username) =>
      api.put('me/username', body: {'username': username});
}
