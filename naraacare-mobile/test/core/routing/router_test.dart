import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/routing/app_router.dart';
import 'package:naraacare/core/routing/guards.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/deep_link_validator.dart';
import 'package:naraacare/core/session/auth_controller.dart';

import '../../helpers/harness.dart';

void main() {
  group('authRedirect follows the document flow (doc 02 section 2.0)', () {
    const cases = <(AuthStatus, String, String?)>[
      (AuthStatus.unknown, Routes.home, Routes.splash),
      (AuthStatus.unknown, Routes.splash, null),
      (AuthStatus.introNeeded, Routes.splash, Routes.intro),
      (AuthStatus.introNeeded, Routes.welcome, Routes.intro),
      (AuthStatus.signedOut, Routes.intro, Routes.welcome),
      (AuthStatus.signedOut, Routes.home, Routes.welcome),
      (AuthStatus.signedOut, Routes.signIn, null),
      (AuthStatus.signedOut, '/invite/PRIYA26', Routes.welcome),
      (AuthStatus.onboarding, Routes.home, Routes.onboarding),
      (AuthStatus.onboarding, Routes.onboarding, null),
      (AuthStatus.signedIn, Routes.welcome, Routes.home),
      (AuthStatus.signedIn, Routes.onboarding, Routes.home),
      (AuthStatus.signedIn, Routes.profile, null),
      (AuthStatus.signedIn, '/invite/PRIYA26', null),
      (AuthStatus.signedIn, '/admin', Routes.home),
    ];
    for (final (status, location, expected) in cases) {
      test('$status at $location -> $expected', () {
        expect(authRedirect(status, location), expected);
      });
    }
  });

  group('deep links', () {
    const validator = DeepLinkValidator('naraacare.app');

    test('accepts our own https invite and circle links', () {
      final invite = validator.parse(
        Uri.parse('https://naraacare.app/invite/priya26'),
      );
      expect((invite! as InviteLink).code, 'PRIYA26');
      final circle = validator.parse(
        Uri.parse('https://naraacare.app/circle/AbC_def-1234567890'),
      );
      expect(circle, isA<CircleLink>());
    });

    for (final link in [
      'http://naraacare.app/invite/PRIYA26', // not https
      'https://evil.example/invite/PRIYA26', // other domain
      'https://naraacare.app.evil.example/invite/PRIYA26',
      'https://user@naraacare.app/invite/PRIYA26', // user info
      'https://naraacare.app:8443/invite/PRIYA26', // port
      'https://naraacare.app/invite/<script>',
      'https://naraacare.app/invite/PRIYA26/extra',
      'https://naraacare.app/circle/short',
      'https://naraacare.app/admin/x',
      'javascript:alert(1)',
    ]) {
      test('refuses $link', () {
        expect(validator.parse(Uri.parse(link)), isNull);
      });
    }
  });

  group('router', () {
    Future<(GoRouter, AuthController)> pump(
      WidgetTester tester,
      Harness harness,
    ) async {
      final auth = harness.authController();
      final router = buildRouter(auth);
      await tester.pumpWidget(harness.wrapRouter(router));
      await tester.pumpAndSettle();
      return (router, auth);
    }

    testWidgets('first install: splash -> intro', (tester) async {
      final harness = Harness();
      final (router, _) = await pump(tester, harness);
      expect(router.state.uri.path, Routes.intro);
    });

    testWidgets('returning user without a session: welcome', (tester) async {
      final harness = Harness();
      await harness.storage.markIntroSeen();
      final (router, auth) = await pump(tester, harness);
      expect(router.state.uri.path, Routes.welcome);
      await auth.signedIn(tokenPair(onboardingRequired: true));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Routes.onboarding);
      await auth.onboardingCompleted();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Routes.home);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('stored session: silent refresh -> home', (tester) async {
      final harness = Harness()..respond(200, tokenPairJson());
      await harness.signIn();
      final (router, _) = await pump(tester, harness);
      expect(router.state.uri.path, Routes.home);
      expect(harness.server.paths.first, 'auth/token/refresh');
    });

    testWidgets('a refused refresh signs out', (tester) async {
      final harness = Harness()
        ..respond(401, {
          'error': {'code': 'UNAUTHENTICATED'},
        });
      await harness.signIn();
      await harness.storage.markIntroSeen();
      final (router, _) = await pump(tester, harness);
      expect(router.state.uri.path, Routes.welcome);
      expect(await harness.session.tokens(), isNull);
    });

    testWidgets('offline with a session stays signed in', (tester) async {
      final harness = Harness()..server.offline = true;
      await harness.signIn();
      final (router, _) = await pump(tester, harness);
      expect(router.state.uri.path, Routes.home);
    });

    testWidgets('invalid deep link parameters go home', (tester) async {
      final harness = Harness()..respond(200, tokenPairJson());
      await harness.signIn();
      final (router, _) = await pump(tester, harness);
      router.go('/invite/<b>');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Routes.home);
      router.go('/invite/PRIYA26');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/invite/PRIYA26');
    });
  });
}
