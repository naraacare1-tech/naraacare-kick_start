import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/l10n/generated/app_localizations_en.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/features/home/presentation/home_screen.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/harness.dart';

void main() {
  late AppHarness h;

  setUp(() => h = AppHarness());

  /// Signed in, onboarded, at Home.
  Future<void> home(WidgetTester tester, {String? username = 'priya.s'}) async {
    await h.signIn();
    h.server
      ..on('auth/token/refresh', 200, tokenPairJson())
      ..on('me', 200, meJson(username: username))
      ..on('reference/bootstrap', 200, referenceBootstrap)
      ..on('me/goal-options', 200, goalOptions);
    await h.pump(tester);
    expect(h.location, Routes.home);
  }

  group('greeting by local time', () {
    final l10n = AppLocalizationsEn();
    for (final (hour, expected) in [
      (5, l10n.greetingMorning),
      (11, l10n.greetingMorning),
      (12, l10n.greetingAfternoon),
      (16, l10n.greetingAfternoon),
      (17, l10n.greetingEvening),
      (23, l10n.greetingEvening),
      (4, l10n.greetingEvening),
    ]) {
      test('$hour:00 -> $expected', () {
        expect(greetingFor(l10n, DateTime(2026, 10, 31, hour)), expected);
      });
    }
  });

  testWidgets('Home greets by first name', (tester) async {
    await home(tester);
    expect(find.textContaining('Priya'), findsOneWidget);
    expect(find.textContaining('Priya Sharma'), findsNothing);
  });

  group('H2 username sheet', () {
    testWidgets('offered once when no username; Set up later closes it', (
      tester,
    ) async {
      await home(tester, username: null);
      expect(find.text(h.l10n.usernameSheetTitle), findsOneWidget);
      await h.tapText(tester, h.l10n.setUpLater);
      expect(find.text(h.l10n.usernameSheetTitle), findsNothing);
      await h.go(tester, Routes.profile);
      await h.go(tester, Routes.home);
      expect(find.text(h.l10n.usernameSheetTitle), findsNothing);
    });

    testWidgets('not offered when a username exists', (tester) async {
      await home(tester);
      expect(find.text(h.l10n.usernameSheetTitle), findsNothing);
    });

    testWidgets('availability check (debounced), then save', (tester) async {
      await home(tester, username: null);
      h.server
        ..on('usernames/availability', 200, {'available': false})
        ..on('usernames/availability', 200, {'available': true})
        ..on('me/username', 204);
      final field = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, 'priya');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(field, 'priya.s');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      // Only the last value was checked.
      expect(
        h.server.requests.where((r) => r.$2 == 'usernames/availability'),
        hasLength(1),
      );
      expect(find.text(h.l10n.usernameTaken), findsOneWidget);

      await tester.enterText(field, 'priya.s2');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text(h.l10n.usernameAvailable), findsOneWidget);
      await h.tapText(tester, h.l10n.saveButton);
      expect(h.server.bodiesFor('me/username').single, {
        'username': 'priya.s2',
      });
      expect(find.text(h.l10n.usernameSheetTitle), findsNothing);
    });
  });

  group('settings', () {
    Future<void> settings(WidgetTester tester) async {
      await home(tester);
      await h.go(tester, Routes.settings);
      expect(find.text(h.l10n.settingsTitle), findsOneWidget);
    }

    testWidgets('menu shows the user and opens the S07 screens', (
      tester,
    ) async {
      await settings(tester);
      expect(find.text('@priya.s'), findsOneWidget);
      await h.tapText(tester, h.l10n.editProfile);
      expect(h.location, Routes.editProfile);
      await h.go(tester, Routes.settings);
      await h.tapText(tester, h.l10n.account);
      expect(h.location, Routes.account);
      expect(find.text('priya@example.com'), findsOneWidget);
    });

    testWidgets('Log Out: confirm, revoke on the API, back to Welcome', (
      tester,
    ) async {
      h.server.on('auth/logout', 204);
      await settings(tester);
      await h.tapText(tester, h.l10n.logOut);
      await h.tapText(tester, h.l10n.cancel);
      expect(h.auth.status, AuthStatus.signedIn);
      await h.tapText(tester, h.l10n.logOut);
      await tester.tap(find.widgetWithText(TextButton, h.l10n.logOut));
      await tester.pumpAndSettle();
      expect(h.server.paths, contains('auth/logout'));
      expect(h.auth.status, AuthStatus.signedOut);
      expect(h.location, Routes.welcome);
      expect(await h.session.tokens(), isNull);
    });

    testWidgets('Log Out offline still signs out locally', (tester) async {
      await settings(tester);
      h.server.offline = true;
      await h.tapText(tester, h.l10n.logOut);
      await tester.tap(find.widgetWithText(TextButton, h.l10n.logOut));
      await tester.pumpAndSettle();
      expect(h.auth.status, AuthStatus.signedOut);
    });

    testWidgets('Edit Profile sends only the changed fields', (tester) async {
      h.server.on('me/profile', 200, {'me': meJson(), 'targets_today': null});
      await settings(tester);
      await h.go(tester, Routes.editProfile);
      await h.type(tester, h.l10n.fullNameLabel, 'Priya S Sharma');
      await h.type(tester, h.l10n.ageLabel, '29');
      await h.tapText(tester, h.l10n.saveButton);
      expect(h.server.bodiesFor('me/profile').single, {
        'full_name': 'Priya S Sharma',
        'age_years': 29,
      });
      expect(find.text(h.l10n.profileSaved), findsOneWidget);
    });

    testWidgets('Edit Profile: changing sex also updates the avatar', (
      tester,
    ) async {
      h.server.on('me/profile', 200, {'me': meJson(), 'targets_today': null});
      await settings(tester);
      await h.go(tester, Routes.editProfile);
      await tester.tap(find.text(h.l10n.sexFemale));
      await tester.pumpAndSettle();
      await tester.tap(find.text(h.l10n.sexMale).last);
      await tester.pumpAndSettle();
      await h.tapText(tester, h.l10n.saveButton);
      expect(h.server.bodiesFor('me/profile').single, {
        'biological_sex': 'male',
        'avatar_code': 'male_mesomorph',
      });
    });

    testWidgets('Edit Profile: no change, no request', (tester) async {
      await settings(tester);
      await h.go(tester, Routes.editProfile);
      await h.tapText(tester, h.l10n.saveButton);
      expect(h.server.bodiesFor('me/profile'), isEmpty);
    });

    testWidgets('Username: once-per-3-months refusal is shown', (tester) async {
      h.server
        ..on('usernames/availability', 200, {'available': true})
        ..on('me/username', 403, apiError('USERNAME_CHANGE_TOO_SOON'));
      await settings(tester);
      await h.go(tester, Routes.username);
      await tester.enterText(find.byType(TextFormField), 'priya.new');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await h.tapText(tester, h.l10n.saveButton);
      expect(find.text(h.l10n.usernameTooSoon), findsOneWidget);
    });

    testWidgets('Change password', (tester) async {
      h.server
        ..on('auth/password/change', 401, apiError('INVALID_CREDENTIALS'))
        ..on('auth/password/change', 204);
      await settings(tester);
      await h.go(tester, Routes.changePassword);
      await h.type(tester, h.l10n.currentPasswordLabel, 'Wr0ngPass');
      await h.type(tester, h.l10n.newPasswordLabel, 'NewStr0ng1');
      await h.type(tester, h.l10n.confirmPasswordLabel, 'NewStr0ng1');
      await h.tapText(tester, h.l10n.saveButton);
      expect(find.text(h.l10n.invalidCredentials), findsOneWidget);

      await h.type(tester, h.l10n.currentPasswordLabel, 'OldStr0ng1');
      await h.tapText(tester, h.l10n.saveButton);
      expect(h.server.bodiesFor('auth/password/change').last, {
        'current_password': 'OldStr0ng1',
        'new_password': 'NewStr0ng1',
        'confirm_password': 'NewStr0ng1',
      });
      expect(find.text(h.l10n.passwordUpdated), findsOneWidget);
      expect(h.location, Routes.account);
    });
  });
}
