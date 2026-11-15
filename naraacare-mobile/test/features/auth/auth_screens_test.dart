import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/harness.dart';

const _challenge = '0190f5d2-3c4b-7a1e-9f00-00000000c0de';

void main() {
  late AppHarness h;

  setUp(() => h = AppHarness());

  group('A2 Welcome', () {
    testWidgets('Get Started opens Sign Up; Sign In opens Sign In', (
      tester,
    ) async {
      await h.pump(tester);
      expect(h.location, Routes.welcome);
      await h.tapText(tester, h.l10n.welcomeGetStarted);
      expect(h.location, Routes.signUp);
      await h.go(tester, Routes.welcome);
      await h.tapText(tester, h.l10n.signInLink);
      expect(h.location, Routes.signIn);
    });
  });

  group('A3 Sign Up', () {
    Future<void> fill(
      WidgetTester tester, {
      String email = 'priya@example.com',
      String password = 'Str0ngPass',
      String? confirm,
      bool terms = true,
    }) async {
      await h.type(tester, h.l10n.emailLabel, email);
      await h.type(tester, h.l10n.passwordLabel, password);
      await h.type(tester, h.l10n.confirmPasswordLabel, confirm ?? password);
      if (terms) {
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
      }
    }

    testWidgets('success sends the policy versions and opens the code', (
      tester,
    ) async {
      h.server
        ..on('reference/policies', 200, policies)
        ..on('auth/signup', 201, {
          'challenge_id': _challenge,
          'expires_in_s': 300,
          'resend_after_s': 30,
        });
      await h.pump(tester);
      await h.go(tester, Routes.signUp);
      await fill(tester, email: '  Priya@Example.com ');
      await h.tapText(tester, h.l10n.signUpButton);

      final body = h.server.bodiesFor('auth/signup').single! as Map;
      expect(body['email'], 'Priya@Example.com');
      expect(body['accept_terms'], isTrue);
      expect(body['policy_versions'], {
        'terms': '2026-10',
        'privacy': '2026-10b',
      });
      expect(body['installation_id'], await h.storage.installationId());
      expect(h.location, Routes.verifyEmail);
      expect(find.text('Priya@Example.com'), findsOneWidget);
    });

    testWidgets('terms required', (tester) async {
      await h.pump(tester);
      await h.go(tester, Routes.signUp);
      await fill(tester, terms: false);
      await h.tapText(tester, h.l10n.signUpButton);
      expect(find.text(h.l10n.termsRequired), findsOneWidget);
      expect(h.server.bodiesFor('auth/signup'), isEmpty);
    });

    testWidgets('password mismatch', (tester) async {
      await h.pump(tester);
      await h.go(tester, Routes.signUp);
      await fill(tester, confirm: 'Different1');
      await h.tapText(tester, h.l10n.signUpButton);
      expect(find.text(h.l10n.validationMismatch), findsOneWidget);
      expect(h.server.bodiesFor('auth/signup'), isEmpty);
    });

    testWidgets('weak password is refused locally', (tester) async {
      await h.pump(tester);
      await h.go(tester, Routes.signUp);
      await fill(tester, password: 'alllowercase');
      await h.tapText(tester, h.l10n.signUpButton);
      expect(find.text(h.l10n.validationWeakPassword), findsWidgets);
      expect(h.server.bodiesFor('auth/signup'), isEmpty);
    });

    testWidgets('email already registered shows on the email field', (
      tester,
    ) async {
      h.server
        ..on('reference/policies', 200, policies)
        ..on('auth/signup', 409, apiError('EMAIL_REGISTERED'));
      await h.pump(tester);
      await h.go(tester, Routes.signUp);
      await fill(tester);
      await h.tapText(tester, h.l10n.signUpButton);
      expect(find.text(h.l10n.emailRegistered), findsOneWidget);
      expect(h.location, Routes.signUp);
    });

    testWidgets('show/hide password toggles obscuring', (tester) async {
      await h.pump(tester);
      await h.go(tester, Routes.signUp);
      EditableText password() => tester.widget<EditableText>(
        find.descendant(
          of: find.ancestor(
            of: find.text(h.l10n.passwordLabel),
            matching: find.byType(TextFormField),
          ),
          matching: find.byType(EditableText),
        ),
      );
      expect(password().obscureText, isTrue);
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pump();
      expect(password().obscureText, isFalse);
    });
  });

  group('A4/A5 email code', () {
    Future<void> open(WidgetTester tester) async {
      await h.pump(tester);
      await h.go(
        tester,
        Routes.verifyEmail,
        extra: const CodeArgs(
          challengeId: _challenge,
          email: 'priya@example.com',
          resendAfterSeconds: 3,
        ),
      );
    }

    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextFormField), code);
      await tester.pumpAndSettle();
    }

    testWidgets('right code signs in and shows Email Verified', (tester) async {
      h.server.on(
        'auth/otp/verify',
        200,
        tokenPairJson(onboardingRequired: true),
      );
      await open(tester);
      await enterCode(tester, '123456');
      final body = h.server.bodiesFor('auth/otp/verify').single! as Map;
      expect(body['code'], '123456');
      expect(body['challenge_id'], _challenge);
      expect(h.auth.status, AuthStatus.onboarding);
      expect(h.location, Routes.emailVerified);
      expect(find.text(h.l10n.emailVerifiedTitle), findsOneWidget);
      expect((await h.session.tokens())!.accessToken, 'access-new');

      await h.tapText(tester, h.l10n.actionContinue);
      expect(h.location, Routes.onboarding);
    });

    testWidgets('wrong code shows attempts left and clears the boxes', (
      tester,
    ) async {
      h.server.on(
        'auth/otp/verify',
        422,
        apiError('OTP_INVALID', {'attempts_left': 2}),
      );
      await open(tester);
      await enterCode(tester, '000000');
      expect(find.text(h.l10n.otpInvalidAttempts(2)), findsOneWidget);
      expect(h.auth.status, AuthStatus.signedOut);
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('expired and locked codes', (tester) async {
      h.server
        ..on('auth/otp/verify', 410, apiError('OTP_EXPIRED'))
        ..on('auth/otp/verify', 423, apiError('OTP_LOCKED'));
      await open(tester);
      await enterCode(tester, '111111');
      expect(find.text(h.l10n.otpExpired), findsOneWidget);
      await enterCode(tester, '222222');
      expect(find.text(h.l10n.otpLocked), findsOneWidget);
    });

    testWidgets('resend: countdown, then "New code sent"', (tester) async {
      h.server.on('auth/otp/resend', 202, {'resend_after_s': 30});
      await open(tester);
      expect(find.text(h.l10n.resendIn('00:03')), findsOneWidget);
      expect(find.text(h.l10n.resendCode), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await h.tapText(tester, h.l10n.resendCode);
      expect(h.server.bodiesFor('auth/otp/resend').single, {
        'challenge_id': _challenge,
      });
      expect(find.text(h.l10n.codeResent), findsOneWidget);
      expect(find.text(h.l10n.resendIn('00:30')), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('pasting letters keeps digits only', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextFormField), '12ab34');
      await tester.pump();
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, '1234');
      expect(h.server.bodiesFor('auth/otp/verify'), isEmpty);
    });

    testWidgets('opened without arguments goes back to Sign Up', (
      tester,
    ) async {
      await h.pump(tester);
      await h.go(tester, Routes.verifyEmail);
      expect(h.location, Routes.signUp);
    });
  });

  group('A6 Sign In', () {
    Future<void> signIn(WidgetTester tester) async {
      await h.pump(tester);
      await h.go(tester, Routes.signIn);
      await h.type(tester, h.l10n.emailLabel, 'priya@example.com');
      await h.type(tester, h.l10n.passwordLabel, 'Str0ngPass');
      await h.tapText(tester, h.l10n.signInButton);
    }

    testWidgets('success goes Home', (tester) async {
      h.server
        ..on('auth/login', 200, tokenPairJson())
        ..on('me', 200, meJson());
      await signIn(tester);
      expect(h.auth.status, AuthStatus.signedIn);
      expect(h.location, Routes.home);
    });

    testWidgets('unfinished onboarding resumes onboarding', (tester) async {
      h.server.on('auth/login', 200, tokenPairJson(onboardingRequired: true));
      await signIn(tester);
      expect(h.location, Routes.onboarding);
    });

    testWidgets('wrong credentials: one generic message, password cleared', (
      tester,
    ) async {
      h.server.on('auth/login', 401, apiError('INVALID_CREDENTIALS'));
      await signIn(tester);
      expect(find.text(h.l10n.invalidCredentials), findsOneWidget);
      final password = tester.widget<TextFormField>(
        find.ancestor(
          of: find.text(h.l10n.passwordLabel),
          matching: find.byType(TextFormField),
        ),
      );
      expect(password.controller!.text, isEmpty);
      expect(h.auth.status, AuthStatus.signedOut);
    });

    testWidgets('lockout shows the wait in minutes', (tester) async {
      h.server.on(
        'auth/login',
        423,
        apiError('ACCOUNT_LOCKED', {'retry_after_s': 600}),
      );
      await signIn(tester);
      expect(find.text(h.l10n.accountLocked(10)), findsOneWidget);
    });

    testWidgets('unverified email opens the code screen', (tester) async {
      h.server.on(
        'auth/login',
        403,
        apiError('EMAIL_NOT_VERIFIED', {'challenge_id': _challenge}),
      );
      await signIn(tester);
      expect(h.location, Routes.verifyEmail);
    });

    testWidgets('Forgot Password? link', (tester) async {
      await h.pump(tester);
      await h.go(tester, Routes.signIn);
      await h.tapText(tester, h.l10n.forgotPasswordLink);
      expect(h.location, Routes.forgotPassword);
    });
  });

  group('A7-A10 password reset', () {
    testWidgets('email -> code -> new password -> changed', (tester) async {
      h.server
        ..on('auth/password/forgot', 202, {'challenge_id': _challenge})
        ..on('auth/password/reset', 204);
      await h.pump(tester);
      await h.go(tester, Routes.forgotPassword);
      await h.type(tester, h.l10n.emailLabel, 'priya@example.com');
      await h.tapText(tester, h.l10n.resetPasswordButton);
      expect(h.location, Routes.resetCode);
      expect(find.text(h.l10n.resetCodeBody), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '654321');
      await tester.pumpAndSettle();
      expect(h.location, Routes.newPassword);
      expect(h.server.bodiesFor('auth/password/reset'), isEmpty);

      await h.type(tester, h.l10n.newPasswordLabel, 'NewStr0ng');
      await h.type(tester, h.l10n.confirmPasswordLabel, 'NewStr0ng');
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check_circle).first).icon,
        Icons.check_circle,
      );
      await h.tapText(tester, h.l10n.resetPasswordButton);
      expect(h.server.bodiesFor('auth/password/reset').single, {
        'challenge_id': _challenge,
        'code': '654321',
        'new_password': 'NewStr0ng',
        'confirm_password': 'NewStr0ng',
      });
      expect(h.location, Routes.passwordChanged);
      await h.tapText(tester, h.l10n.backToSignIn);
      expect(h.location, Routes.signIn);
    });

    testWidgets('rules checklist follows the typed password', (tester) async {
      await h.pump(tester);
      await h.go(
        tester,
        Routes.newPassword,
        extra: const NewPasswordArgs(challengeId: _challenge, code: '1'),
      );
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await h.type(tester, h.l10n.newPasswordLabel, 'abcdefgh');
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await h.type(tester, h.l10n.newPasswordLabel, 'Abcdefg1');
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    });

    testWidgets('a reused password is refused with fixed copy', (tester) async {
      h.server.on('auth/password/reset', 422, apiError('PASSWORD_REUSED'));
      await h.pump(tester);
      await h.go(
        tester,
        Routes.newPassword,
        extra: const NewPasswordArgs(challengeId: _challenge, code: '654321'),
      );
      await h.type(tester, h.l10n.newPasswordLabel, 'OldStr0ng');
      await h.type(tester, h.l10n.confirmPasswordLabel, 'OldStr0ng');
      await h.tapText(tester, h.l10n.resetPasswordButton);
      expect(find.text(h.l10n.passwordReused), findsOneWidget);
      expect(h.location, Routes.newPassword);
    });
  });
}
