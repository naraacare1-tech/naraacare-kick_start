import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';

/// What the user has entered so far, kept while moving between steps.
/// Every step is also saved to the API (PUT /me/onboarding/steps/n), so a
/// restart resumes from the server copy (GET /me/onboarding), not from here.
/// Values are metric; [feetInches] and [pounds] only change the display.
class OnboardingDraft {
  String? sex;
  String? fullName;
  double? heightCm;
  double? weightKg;
  String? goal;
  double? targetWeightKg;
  List<String> conditions = [];
  int? age;
  String? activity;
  String? bodyType;
  bool feetInches = false;
  bool pounds = false;

  /// Prefills from the server copy when resuming.
  void fill(Profile p) {
    sex ??= p.biologicalSex;
    fullName ??= p.fullName;
    heightCm ??= p.heightCm;
    weightKg ??= p.weightKg;
    goal ??= p.weightGoal;
    targetWeightKg ??= p.targetWeightKg;
    if (conditions.isEmpty) conditions = [...p.conditionCodes];
    age ??= p.ageYears;
    activity ??= p.activityLevel;
    bodyType ??= p.bodyType;
  }

  /// The avatar is sex + body type; step 1 stores a default body type until
  /// step 6 picks the real one (sent with PATCH after completion).
  String avatarCode() => '${sex}_${bodyType ?? 'mesomorph'}';
}

final onboardingDraftProvider = Provider<OnboardingDraft>(
  (ref) => OnboardingDraft(),
);
