import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/session/auth_controller.dart';

import '../helpers/app_harness.dart';
import '../helpers/harness.dart';

/// The whole first-run journey against a mocked API (doc 02 section 2.0):
/// intro -> Welcome -> Sign Up -> code -> Email Verified -> onboarding 1-6
/// -> result -> consent -> saved -> Home. Shared by the widget test and the
/// on-device integration test.
Future<void> signUpToHome(WidgetTester tester) async {
  final h = AppHarness();
  final steps = <int, Map<String, Object?>>{};
  h.server
    ..on('reference/policies', 200, policies)
    ..on('reference/bootstrap', 200, referenceBootstrap)
    ..on('auth/signup', 201, {
      'challenge_id': '0190f5d2-3c4b-7a1e-9f00-00000000c0de',
      'expires_in_s': 300,
      'resend_after_s': 30,
    })
    ..on('auth/otp/verify', 200, tokenPairJson(onboardingRequired: true))
    ..on('me/onboarding', 200, {
      'current_step': 0,
      'completed': false,
      'data_so_far': {
        for (final key in profileJson().keys) key: null,
        'medical_condition_codes': <String>[],
      },
    })
    ..on('me/goal-options', 200, goalOptions)
    ..on('calculations/preview', 200, {
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
    })
    ..on('me/onboarding/complete', 201, {})
    ..on('me/profile', 200, {'me': meJson(), 'targets_today': null})
    ..on('me', 200, meJson())
    ..on('me/settings', 204);
  for (var step = 1; step <= 6; step++) {
    h.server.on('me/onboarding/steps/$step', 200, {'current_step': step});
  }

  // First install: intro slides, skipped.
  await h.pump(tester, introSeen: false);
  expect(h.location, Routes.intro);
  await h.tapText(tester, h.l10n.introSkip);
  expect(h.location, Routes.welcome);

  // Sign up.
  await h.tapText(tester, h.l10n.welcomeGetStarted);
  await h.type(tester, h.l10n.emailLabel, 'priya@example.com');
  await h.type(tester, h.l10n.passwordLabel, 'Str0ngPass');
  await h.type(tester, h.l10n.confirmPasswordLabel, 'Str0ngPass');
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await h.tapText(tester, h.l10n.signUpButton);

  // Code -> Email Verified -> onboarding start.
  await tester.enterText(find.byType(TextFormField), '123456');
  await tester.pumpAndSettle();
  expect(h.location, Routes.emailVerified);
  await h.tapText(tester, h.l10n.actionContinue);
  await h.tapText(tester, h.l10n.onboardingIntroButton);
  expect(h.location, Routes.onboardingStep(1));

  // Steps 1-6.
  await h.tapText(tester, h.l10n.sexFemale);
  await h.type(tester, h.l10n.fullNameLabel, 'Priya Sharma');
  await h.tapText(tester, h.l10n.nextButton);
  await h.tapText(tester, h.l10n.nextButton); // height: 160 cm
  await tester.enterText(find.byType(TextFormField), '62');
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mild Loss').last);
  await tester.pumpAndSettle();
  await h.tapText(tester, h.l10n.nextButton);
  await tester.enterText(find.byType(TextFormField).first, '58');
  await h.tapText(tester, h.l10n.nextButton);
  await tester.enterText(find.byType(TextFormField), '28');
  await h.tapText(tester, 'Active (Exercise 3-5 days/week)');
  await h.tapText(tester, h.l10n.nextButton);
  await h.tapText(tester, 'Mesomorph');
  await h.tapText(tester, h.l10n.nextButton);
  for (var step = 1; step <= 6; step++) {
    steps[step] =
        h.server.bodiesFor('me/onboarding/steps/$step').single!
            as Map<String, Object?>;
  }
  expect(steps[2], {'height_cm': '160.0'});
  expect(steps[3], {'weight_kg': '62.00', 'weight_goal': 'mild_loss'});
  expect(steps[6], {'body_type': 'mesomorph'});

  // Result -> consent -> saved -> Home.
  expect(h.location, Routes.onboardingResult);
  expect(find.text(h.l10n.kcalValue(1714)), findsOneWidget);
  await h.tapText(tester, h.l10n.saveAvatar);
  await h.tapText(tester, h.l10n.consentTerms);
  await h.tapText(tester, h.l10n.consentPrivacy);
  await h.tapText(tester, h.l10n.consentHealth);
  await h.tapText(tester, h.l10n.consentAgree);
  expect(h.location, Routes.onboardingSaved);
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  expect(h.auth.status, AuthStatus.signedIn);
  expect(h.location, Routes.home);
  expect(find.textContaining('Priya'), findsOneWidget);
  expect(await h.storage.introSeen(), isTrue);
  expect((await h.session.tokens())!.refreshToken, 'refresh-new');
}
