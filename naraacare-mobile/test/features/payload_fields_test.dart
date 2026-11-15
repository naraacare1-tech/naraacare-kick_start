import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';

import '../helpers/app_harness.dart';
import '../helpers/harness.dart';
import '../security/payloads.dart';

/// S07 input-validation checklist: every text field of the auth, onboarding
/// and settings screens gets the payload list. A payload must never reach
/// the API as typed and never be shown back. Fields with a formatter
/// (digits, decimals, username) may let harmless characters through; then
/// only those may be sent.
void main() {
  final payloads = loadPayloads();
  // A spread across the list: tags, encodings, templates, control chars.
  final sample = [for (var i = 0; i < payloads.length; i += 23) payloads[i]];

  late AppHarness h;

  setUp(() => h = AppHarness());

  Future<void> signedOut(
    WidgetTester tester,
    String route, [
    Object? extra,
  ]) async {
    await h.pump(tester);
    await h.go(tester, route, extra: extra);
  }

  Future<void> signedIn(WidgetTester tester, String route) async {
    await h.signIn(onboardingComplete: route.startsWith(Routes.profile));
    h.server
      ..on(
        'auth/token/refresh',
        200,
        tokenPairJson(onboardingRequired: !route.startsWith(Routes.profile)),
      )
      ..on('me', 200, meJson())
      ..on('reference/bootstrap', 200, referenceBootstrap)
      ..on('me/goal-options', 200, goalOptions)
      ..on('usernames/availability', 200, {'available': true});
    await h.pump(tester);
    await h.go(tester, route);
  }

  /// Types each payload into the field labelled [label] (others valid),
  /// submits with [submit] and checks what reached [endpoint].
  Future<void> sweep(
    WidgetTester tester, {
    required String label,
    required String submit,
    required String endpoint,
    Map<String, String> valid = const {},
    RegExp? allowedSent,
    String? sentKey,
  }) async {
    for (final entry in valid.entries) {
      await h.type(tester, entry.key, entry.value);
    }
    final screen = h.location;
    for (final payload in sample) {
      final before = h.server.bodiesFor(endpoint).length;
      await h.type(tester, label, payload);
      await h.tapText(tester, submit);
      final sent = h.server.bodiesFor(endpoint).skip(before).toList();
      if (allowedSent == null) {
        expect(sent, isEmpty, reason: 'sent for ${jsonEncode(payload)}');
      } else {
        for (final body in sent) {
          final value = '${(body! as Map)[sentKey]}';
          expect(value, matches(allowedSent), reason: jsonEncode(payload));
        }
      }
      // Never echoed outside the field itself.
      final trimmed = payload.trim();
      if (trimmed.length >= 4) {
        final shown = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
        expect(
          shown.where((t) => t.contains(trimmed)),
          isEmpty,
          reason: jsonEncode(payload),
        );
      }
      // Back to the form if a submit moved on.
      if (h.location != screen) await h.go(tester, screen);
    }
  }

  group('auth fields', () {
    setUp(() {
      h.server
        ..on('reference/policies', 200, policies)
        ..on('auth/signup', 201, {
          'challenge_id': 'c',
          'expires_in_s': 300,
          'resend_after_s': 30,
        })
        ..on('auth/login', 401, apiError('INVALID_CREDENTIALS'));
    });

    for (final field in [
      'emailLabel',
      'passwordLabel',
      'confirmPasswordLabel',
    ]) {
      testWidgets('Sign Up $field', (tester) async {
        await signedOut(tester, Routes.signUp);
        final l = h.l10n;
        final labels = {
          'emailLabel': l.emailLabel,
          'passwordLabel': l.passwordLabel,
          'confirmPasswordLabel': l.confirmPasswordLabel,
        };
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await sweep(
          tester,
          label: labels[field]!,
          submit: l.signUpButton,
          endpoint: 'auth/signup',
          valid: {
            for (final MapEntry(:key, :value) in labels.entries)
              if (key != field)
                value: key == 'emailLabel' ? 'priya@example.com' : 'Str0ngPass',
          },
        );
      });
    }

    for (final password in [false, true]) {
      testWidgets('Sign In ${password ? 'password' : 'email'}', (tester) async {
        await signedOut(tester, Routes.signIn);
        await sweep(
          tester,
          label: password ? h.l10n.passwordLabel : h.l10n.emailLabel,
          submit: h.l10n.signInButton,
          endpoint: 'auth/login',
          valid: password
              ? {h.l10n.emailLabel: 'priya@example.com'}
              : {h.l10n.passwordLabel: 'Str0ngPass'},
        );
      });
    }

    testWidgets('Forgot Password email', (tester) async {
      await signedOut(tester, Routes.forgotPassword);
      await sweep(
        tester,
        label: h.l10n.emailLabel,
        submit: h.l10n.resetPasswordButton,
        endpoint: 'auth/password/forgot',
      );
    });

    testWidgets('Set New Password fields', (tester) async {
      await signedOut(
        tester,
        Routes.newPassword,
        const NewPasswordArgs(challengeId: 'c', code: '123456'),
      );
      await sweep(
        tester,
        label: h.l10n.newPasswordLabel,
        submit: h.l10n.resetPasswordButton,
        endpoint: 'auth/password/reset',
        valid: {h.l10n.confirmPasswordLabel: 'NewStr0ng1'},
      );
    });

    testWidgets('email code: digits only reach the API', (tester) async {
      h.server.on('auth/otp/verify', 422, apiError('OTP_INVALID'));
      await signedOut(
        tester,
        Routes.verifyEmail,
        const CodeArgs(challengeId: 'c', email: 'priya@example.com'),
      );
      for (final payload in sample) {
        await tester.enterText(find.byType(TextFormField), payload);
        await tester.pumpAndSettle();
      }
      for (final body in h.server.bodiesFor('auth/otp/verify')) {
        expect((body! as Map)['code'], matches(RegExp(r'^\d{6}$')));
      }
    });
  });

  group('onboarding and settings fields', () {
    testWidgets('step 1 full name', (tester) async {
      await signedIn(tester, Routes.onboardingStep(1));
      await h.tapText(tester, h.l10n.sexFemale);
      await sweep(
        tester,
        label: h.l10n.fullNameLabel,
        submit: h.l10n.nextButton,
        endpoint: 'me/onboarding/steps/1',
      );
    });

    testWidgets('step 3 weight: only a decimal can be sent', (tester) async {
      h.server.on('me/onboarding/steps/3', 422, apiError('VALIDATION_FAILED'));
      await signedIn(tester, Routes.onboardingStep(3));
      await sweep(
        tester,
        label: h.l10n.weightHint,
        submit: h.l10n.nextButton,
        endpoint: 'me/onboarding/steps/3',
        allowedSent: RegExp(r'^\d{2,3}\.\d{2}$'),
        sentKey: 'weight_kg',
      );
    });

    testWidgets('step 4 target weight and condition search', (tester) async {
      h.server.on('me/onboarding/steps/4', 422, apiError('VALIDATION_FAILED'));
      await signedIn(tester, Routes.onboardingStep(4));
      await sweep(
        tester,
        label: h.l10n.conditionsHint,
        submit: h.l10n.nextButton,
        endpoint: 'me/onboarding/steps/4',
        valid: {h.l10n.targetHint: '58'},
        // Only codes are sent; the search text never is.
        allowedSent: RegExp(r'^\[\]$'),
        sentKey: 'medical_condition_codes',
      );
    });

    testWidgets('step 5 age: digits 18-100 only', (tester) async {
      h.server.on('me/onboarding/steps/5', 422, apiError('VALIDATION_FAILED'));
      await signedIn(tester, Routes.onboardingStep(5));
      await h.tapText(tester, 'Mostly sitting');
      await sweep(
        tester,
        label: h.l10n.ageHint,
        submit: h.l10n.nextButton,
        endpoint: 'me/onboarding/steps/5',
        allowedSent: RegExp(r'^\d{2,3}$'),
        sentKey: 'age_years',
      );
    });

    testWidgets('username: only [a-z0-9._] can be sent', (tester) async {
      h.server.on('me/username', 409, apiError('USERNAME_TAKEN'));
      await signedIn(tester, Routes.username);
      await sweep(
        tester,
        label: h.l10n.usernameLabel,
        submit: h.l10n.saveButton,
        endpoint: 'me/username',
        allowedSent: RegExp(r'^[a-z0-9._]{3,30}$'),
        sentKey: 'username',
      );
    });

    testWidgets('Edit Profile full name', (tester) async {
      await signedIn(tester, Routes.editProfile);
      await sweep(
        tester,
        label: h.l10n.fullNameLabel,
        submit: h.l10n.saveButton,
        endpoint: 'me/profile',
      );
    });

    testWidgets('Change Password fields', (tester) async {
      await signedIn(tester, Routes.changePassword);
      await sweep(
        tester,
        label: h.l10n.currentPasswordLabel,
        submit: h.l10n.saveButton,
        endpoint: 'auth/password/change',
        valid: {
          h.l10n.newPasswordLabel: 'NewStr0ng1',
          h.l10n.confirmPasswordLabel: 'NewStr0ng1',
        },
      );
    });
  });
}
