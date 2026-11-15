import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/features/auth/data/social_sign_in.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/harness.dart';

void main() {
  late AppHarness h;

  setUp(() => h = AppHarness());

  Future<void> openSignIn(WidgetTester tester) async {
    await h.pump(tester);
    await h.go(tester, Routes.signIn);
  }

  testWidgets('Google: raw nonce and id token go to the API; signed in', (
    tester,
  ) async {
    h.server
      ..on('auth/oauth/google', 200, tokenPairJson())
      ..on('me', 200, meJson());
    await openSignIn(tester);
    await h.tapText(tester, h.l10n.signInWithGoogle);
    final body = h.server.bodiesFor('auth/oauth/google').single! as Map;
    expect(body['id_token'], 'google-id-token');
    expect(body['nonce'], 'raw-nonce-g');
    expect(body['installation_id'], isNotEmpty);
    expect(h.auth.status, AuthStatus.signedIn);
    expect(h.location, Routes.home);
  });

  testWidgets('Apple: identity token, code and nonce', (tester) async {
    h.server.on(
      'auth/oauth/apple',
      200,
      tokenPairJson(onboardingRequired: true),
    );
    await openSignIn(tester);
    await h.tapText(tester, h.l10n.signInWithApple);
    final body = h.server.bodiesFor('auth/oauth/apple').single! as Map;
    expect(body, containsPair('identity_token', 'apple-identity-token'));
    expect(body, containsPair('authorization_code', 'apple-code'));
    expect(body, containsPair('nonce', 'raw-nonce-a'));
    expect(h.location, Routes.onboarding);
  });

  testWidgets('no Apple button where Apple is unavailable', (tester) async {
    h.social.appleAvailable = false;
    await openSignIn(tester);
    expect(find.text(h.l10n.signInWithApple), findsNothing);
    expect(find.text(h.l10n.signInWithGoogle), findsOneWidget);
  });

  testWidgets('cancelling is silent', (tester) async {
    h.social.onGoogle = () => throw const SocialSignInCancelled();
    await openSignIn(tester);
    await h.tapText(tester, h.l10n.signInWithGoogle);
    expect(find.byType(NcErrorBanner), findsNothing);
    expect(h.server.requests, isEmpty);
  });

  testWidgets('provider unreachable: A11 banner', (tester) async {
    h.social.onApple = () => throw const SocialSignInFailed();
    await openSignIn(tester);
    await h.tapText(tester, h.l10n.signInWithApple);
    expect(find.text(h.l10n.appleUnavailable), findsOneWidget);
    await h.tapText(tester, h.l10n.actionClose);
    expect(find.byType(NcErrorBanner), findsNothing);
  });

  testWidgets('token refused by the API: generic banner', (tester) async {
    h.server.on('auth/oauth/google', 401, apiError('UNAUTHENTICATED'));
    await openSignIn(tester);
    await h.tapText(tester, h.l10n.signInWithGoogle);
    expect(find.text(h.l10n.socialError), findsOneWidget);
    expect(h.auth.status, AuthStatus.signedOut);
  });

  testWidgets('LINK_REQUIRED: password sheet links and signs in', (
    tester,
  ) async {
    h.server
      ..on(
        'auth/oauth/google',
        409,
        apiError('LINK_REQUIRED', {'link_token': 'link.tok'}),
      )
      ..on('auth/oauth/link', 401, apiError('INVALID_CREDENTIALS'))
      ..on('auth/oauth/link', 200, tokenPairJson())
      ..on('me', 200, meJson());
    await openSignIn(tester);
    await h.tapText(tester, h.l10n.signInWithGoogle);
    expect(find.text(h.l10n.linkAccountTitle), findsOneWidget);

    final sheetPassword = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(sheetPassword, 'Wr0ngPass');
    await h.tapText(tester, h.l10n.linkAccountButton);
    expect(find.text(h.l10n.invalidCredentials), findsOneWidget);

    await tester.enterText(sheetPassword, 'Str0ngPass');
    await h.tapText(tester, h.l10n.linkAccountButton);
    expect(h.server.bodiesFor('auth/oauth/link').last, {
      'link_token': 'link.tok',
      'password': 'Str0ngPass',
      'installation_id': await h.storage.installationId(),
    });
    expect(h.auth.status, AuthStatus.signedIn);
    expect(h.location, Routes.home);
  });
}
