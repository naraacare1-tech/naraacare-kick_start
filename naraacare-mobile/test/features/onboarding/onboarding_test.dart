import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/core/utils/units.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/measure_inputs.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/harness.dart';

Map<String, Object?> onboardingState(int step, {bool completed = false}) => {
  'current_step': step,
  'completed': completed,
  'data_so_far': profileJson(),
};

void main() {
  late AppHarness h;

  setUp(() => h = AppHarness());

  /// Signed in with onboarding to do (stored session, silent refresh).
  Future<void> start(WidgetTester tester) async {
    await h.signIn(onboardingComplete: false);
    h.server
      ..on('auth/token/refresh', 200, tokenPairJson(onboardingRequired: true))
      ..on('reference/bootstrap', 200, referenceBootstrap)
      ..on('me/goal-options', 200, goalOptions);
    await h.pump(tester);
    expect(h.location, Routes.onboarding);
  }

  Map<dynamic, dynamic> sentFor(int step) =>
      h.server.bodiesFor('me/onboarding/steps/$step').last! as Map;

  void stepSaved(int step) =>
      h.server.on('me/onboarding/steps/$step', 200, {'current_step': step});

  group('unit conversion (display only, sent metric)', () {
    test("5'8\" = 172.7 cm and 120 lb = 54.43 kg", () {
      expect(Units.feetInchesToCm(5, 8), 172.7);
      expect(Units.lbToKg(120), 54.43);
      expect(WeightField.kgFrom('120', pounds: true), 54.43);
      expect(WeightField.kgFrom('62.5', pounds: false), 62.5);
    });

    test('weight entry limits', () {
      expect(WeightField.kgFrom('29.99', pounds: false), isNull);
      expect(WeightField.kgFrom('250.01', pounds: false), isNull);
      expect(WeightField.kgFrom('62.555', pounds: false), isNull);
      expect(WeightField.kgFrom('600', pounds: true), isNull);
      expect(WeightField.display(54.43, pounds: true), '120');
      expect(WeightField.display(62.5, pounds: false), '62.50');
    });
  });

  group('resume (GET /me/onboarding)', () {
    for (final (saved, expected) in [
      (0, Routes.onboardingStep(1)),
      (3, Routes.onboardingStep(4)),
      (6, Routes.onboardingResult),
    ]) {
      testWidgets('last saved step $saved -> $expected', (tester) async {
        await start(tester);
        h.server
          ..on('me/onboarding', 200, onboardingState(saved))
          ..on('calculations/preview', 200, preview);
        await h.tapText(tester, h.l10n.onboardingIntroButton);
        expect(h.location, expected);
      });
    }

    testWidgets('already completed: straight to Home', (tester) async {
      await start(tester);
      h.server
        ..on('me/onboarding', 200, onboardingState(6, completed: true))
        ..on('me', 200, meJson());
      await h.tapText(tester, h.l10n.onboardingIntroButton);
      expect(h.auth.status, AuthStatus.signedIn);
      expect(h.location, Routes.home);
    });

    testWidgets('offline: error banner with retry', (tester) async {
      await start(tester);
      h.server.offline = true;
      await h.tapText(tester, h.l10n.onboardingIntroButton);
      expect(find.text(h.l10n.errorNetwork), findsOneWidget);
      expect(h.location, Routes.onboarding);
    });
  });

  testWidgets('step 1: sex + name; avatar code follows the sex', (
    tester,
  ) async {
    await start(tester);
    stepSaved(1);
    await h.go(tester, Routes.onboardingStep(1));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await h.tapText(tester, h.l10n.sexMale);
    await h.type(tester, h.l10n.fullNameLabel, '  Rahul Verma ');
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(1), {
      'biological_sex': 'male',
      'avatar_code': 'male_mesomorph',
      'full_name': 'Rahul Verma',
    });
    expect(h.location, Routes.onboardingStep(2));
  });

  testWidgets("step 2: 5'8\" is sent as 172.7 cm", (tester) async {
    await start(tester);
    stepSaved(2);
    await h.go(tester, Routes.onboardingStep(2));
    await h.tapText(tester, h.l10n.unitFtIn);
    expect(find.text(h.l10n.feetInches(5, 3)), findsOneWidget); // 160 cm
    // Inches wheel: 3 -> 8 (5 rows of 40 px).
    await tester.drag(find.byType(CupertinoPicker).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text(h.l10n.feetInches(5, 8)), findsOneWidget);
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(2), {'height_cm': '172.7'});
  });

  testWidgets('step 3: 120 lb is sent as 54.43 kg; goals from the API', (
    tester,
  ) async {
    await start(tester);
    stepSaved(3);
    await h.go(tester, Routes.onboardingStep(3));
    await h.tapText(tester, h.l10n.unitLb);
    await tester.enterText(find.byType(TextFormField), '120');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final query = h.server.requests.lastWhere((r) => r.$2 == 'me/goal-options');
    expect(query, isNotNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    // Only the allowed goals are offered (moderate_loss is blocked).
    expect(find.text('Moderate Loss'), findsNothing);
    await tester.tap(find.text('Mild Loss').last);
    await tester.pumpAndSettle();
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(3), {'weight_kg': '54.43', 'weight_goal': 'mild_loss'});
  });

  testWidgets('step 3: GOAL_NOT_ALLOWED from the API is shown', (tester) async {
    await start(tester);
    h.server.on(
      'me/onboarding/steps/3',
      422,
      apiError('GOAL_NOT_ALLOWED', {
        'fields': ['weight_goal'],
      }),
    );
    await h.go(tester, Routes.onboardingStep(3));
    await tester.enterText(find.byType(TextFormField), '62');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintain').last);
    await tester.pumpAndSettle();
    await h.tapText(tester, h.l10n.nextButton);
    expect(find.text(h.l10n.goalNotAllowed), findsOneWidget);
    expect(h.location, Routes.onboardingStep(3));
  });

  testWidgets('step 4: healthy range hint, warning, local condition search', (
    tester,
  ) async {
    await start(tester);
    stepSaved(4);
    await h.go(tester, Routes.onboardingStep(4));
    final target = find.byType(TextFormField).first;
    await tester.enterText(target, '60');
    await tester.pump();
    expect(find.text(h.l10n.healthyRange(55, 68)), findsOneWidget);
    await tester.enterText(target, '50');
    await tester.pump();
    expect(find.text(h.l10n.outsideRange(55, 68)), findsOneWidget);
    await tester.enterText(target, '58');
    await tester.pump();

    final requestsBefore = h.server.requests.length;
    await h.type(tester, h.l10n.conditionsHint, 'allergy');
    await tester.pumpAndSettle();
    expect(find.text('Peanut allergy'), findsOneWidget);
    expect(find.text('Hypertension'), findsNothing);
    expect(h.server.requests.length, requestsBefore); // search stays local
    await h.tapText(tester, 'Peanut allergy');
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(4), {
      'target_weight_kg': '58.00',
      'medical_condition_codes': ['peanut_allergy'],
    });
  });

  testWidgets('step 4: no conditions and an empty search box is fine', (
    tester,
  ) async {
    await start(tester);
    stepSaved(4);
    await h.go(tester, Routes.onboardingStep(4));
    await tester.enterText(find.byType(TextFormField).first, '60');
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(4), {
      'target_weight_kg': '60.00',
      'medical_condition_codes': <String>[],
    });
  });

  testWidgets('step 5: age 18-100 and an activity level', (tester) async {
    await start(tester);
    stepSaved(5);
    await h.go(tester, Routes.onboardingStep(5));
    await tester.enterText(find.byType(TextFormField), '17');
    await h.tapText(tester, 'Mostly sitting');
    await h.tapText(tester, h.l10n.nextButton);
    expect(find.text(h.l10n.validationOutOfRange), findsOneWidget);
    expect(h.server.bodiesFor('me/onboarding/steps/5'), isEmpty);

    await tester.enterText(find.byType(TextFormField), '28');
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(5), {'age_years': 28, 'activity_level': 'sedentary'});
  });

  testWidgets('step 6: body type named in the info text', (tester) async {
    await start(tester);
    stepSaved(6);
    h.server.on('me/onboarding', 200, onboardingState(6));
    h.server.on('calculations/preview', 200, preview);
    await h.go(tester, Routes.onboardingStep(6));
    await h.tapText(tester, 'Ectomorph');
    expect(
      find.textContaining(h.l10n.bodyTypeChosen('Ectomorph')),
      findsOneWidget,
    );
    await h.tapText(tester, h.l10n.nextButton);
    expect(sentFor(6), {'body_type': 'ectomorph'});
    expect(h.location, Routes.onboardingResult);
  });

  testWidgets('Go Back walks back through the steps', (tester) async {
    await start(tester);
    await h.go(tester, Routes.onboardingStep(3));
    await h.tapText(tester, h.l10n.goBack);
    expect(h.location, Routes.onboardingStep(2));
    await h.tapText(tester, h.l10n.goBack);
    await h.tapText(tester, h.l10n.goBack);
    expect(h.location, Routes.onboarding);
  });

  group('result, consent, completion', () {
    Future<void> openResult(WidgetTester tester) async {
      await start(tester);
      h.server
        ..on('me/onboarding', 200, onboardingState(6))
        ..on('calculations/preview', 200, preview)
        ..on('reference/policies', 200, policies);
      await h.go(tester, Routes.onboardingResult);
    }

    testWidgets('numbers come from /calculations/preview', (tester) async {
      await openResult(tester);
      expect(find.text(h.l10n.kcalValue(1714)), findsOneWidget);
      expect(find.text(h.l10n.mlValue(2214)), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Mild Loss'), findsOneWidget);
    });

    testWidgets('Edit Details goes back to step 1', (tester) async {
      await openResult(tester);
      await h.tapText(tester, h.l10n.editDetails);
      expect(h.location, Routes.onboardingStep(1));
    });

    testWidgets('consent: the three required boxes gate the button', (
      tester,
    ) async {
      await openResult(tester);
      await h.tapText(tester, h.l10n.saveAvatar);
      final agree = find.widgetWithText(FilledButton, h.l10n.consentAgree);
      expect(tester.widget<FilledButton>(agree).onPressed, isNull);
      await h.tapText(tester, h.l10n.consentTerms);
      await h.tapText(tester, h.l10n.consentPrivacy);
      expect(tester.widget<FilledButton>(agree).onPressed, isNull);
      await h.tapText(tester, h.l10n.consentHealth);
      expect(tester.widget<FilledButton>(agree).onPressed, isNotNull);
    });

    testWidgets('complete: consents, avatar, units, then Home', (tester) async {
      await openResult(tester);
      h.server
        ..on('me/onboarding/complete', 201, {})
        ..on('me/profile', 200, {'me': meJson(), 'targets_today': null})
        ..on('me', 200, meJson())
        ..on('me/settings', 204);
      await h.tapText(tester, h.l10n.saveAvatar);
      await h.tapText(tester, h.l10n.consentTerms);
      await h.tapText(tester, h.l10n.consentPrivacy);
      await h.tapText(tester, h.l10n.consentHealth);
      await h.tapText(tester, h.l10n.consentAgree);

      final complete = h.server.bodiesFor('me/onboarding/complete').single!;
      expect((complete as Map)['consents'], [
        {'purpose': 'terms', 'policy_version': '2026-10', 'granted': true},
        {'purpose': 'privacy', 'policy_version': '2026-10b', 'granted': true},
        {
          'purpose': 'health_data',
          'policy_version': '2026-10b',
          'granted': true,
        },
        {
          'purpose': 'ai_processing',
          'policy_version': '2026-10b',
          'granted': false,
        },
      ]);
      expect(h.server.bodiesFor('me/profile').single, {
        'avatar_code': 'female_mesomorph',
      });
      final settings = h.server.bodiesFor('me/settings').single! as Map;
      expect(settings['height_unit'], 'cm');
      expect(settings.containsKey('sleep_goal_min'), isFalse);
      expect(h.location, Routes.onboardingSaved);
      expect(find.text(h.l10n.savedTitle), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(h.auth.status, AuthStatus.signedIn);
      expect(h.location, Routes.home);
    });

    testWidgets('completion failure offers a retry', (tester) async {
      await openResult(tester);
      h.server
        ..on('me/onboarding/complete', 503, apiError('SERVICE_UNAVAILABLE'))
        ..on('me/onboarding/complete', 201, {})
        ..on('me', 200, meJson());
      await h.tapText(tester, h.l10n.saveAvatar);
      await h.tapText(tester, h.l10n.consentTerms);
      await h.tapText(tester, h.l10n.consentPrivacy);
      await h.tapText(tester, h.l10n.consentHealth);
      await h.tapText(tester, h.l10n.consentAgree);
      expect(h.location, Routes.onboardingGenerating);
      expect(find.text(h.l10n.errorGeneric), findsOneWidget);
      await h.tapText(tester, h.l10n.actionRetry);
      expect(h.location, Routes.onboardingSaved);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(h.location, Routes.home);
    });
  });
}

const preview = <String, Object>{
  'calc_version': 'v1',
  'bmi': '22.8',
  'bmi_category': 'normal',
  'healthy_weight_range_kg': [55, 68],
  'targets': {
    'kcal': 1714,
    'carbs_g': 214,
    'fat_g': 57,
    'protein_g': 86,
    'safety_override': false,
  },
  'water_need_ml': 2214,
};
