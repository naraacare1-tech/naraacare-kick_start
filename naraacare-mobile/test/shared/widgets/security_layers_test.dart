import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naraacare/core/security/biometric_gate.dart';
import 'package:naraacare/core/security/system_prompt.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:naraacare/shared/widgets/app_switcher_privacy.dart';
import 'package:naraacare/shared/widgets/biometric_lock.dart';

import '../../helpers/harness.dart';

class _Authenticator implements Authenticator {
  bool answer = false;
  int calls = 0;

  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return answer;
  }
}

void main() {
  group('BiometricPolicy', () {
    final t0 = DateTime.utc(2026, 10, 31, 9);

    test('locks only when enabled and away for more than a minute', () {
      bool lock({required bool enabled, required int seconds}) =>
          BiometricPolicy.shouldLock(
            enabled: enabled,
            backgroundedAt: t0,
            now: t0.add(Duration(seconds: seconds)),
          );
      expect(lock(enabled: true, seconds: 61), isTrue);
      expect(lock(enabled: true, seconds: 60), isFalse);
      expect(lock(enabled: false, seconds: 600), isFalse);
      expect(
        BiometricPolicy.shouldLock(
          enabled: true,
          backgroundedAt: null,
          now: t0,
        ),
        isFalse,
      );
    });
  });

  group('BiometricLock', () {
    Future<(FixedClock, _Authenticator)> pump(
      WidgetTester tester, {
      required bool enabled,
    }) async {
      final clock = FixedClock(DateTime.utc(2026, 10, 31, 9));
      final auth = _Authenticator();
      await tester.pumpWidget(
        themed(
          BiometricLock(
            enabled: enabled,
            authenticator: auth,
            clock: clock,
            child: const SizedBox.expand(child: Text('health data')),
          ),
        ),
      );
      return (clock, auth);
    }

    Future<void> background(
      WidgetTester tester,
      FixedClock clock,
      Duration away,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(away);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    testWidgets('locks after a long background and unlocks on success', (
      tester,
    ) async {
      final (clock, auth) = await pump(tester, enabled: true);
      await background(tester, clock, const Duration(minutes: 2));
      expect(find.byKey(const Key('biometric-lock')), findsOneWidget);
      expect(auth.calls, 1);

      auth.answer = true;
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.byKey(const Key('biometric-lock')), findsNothing);
      expect(auth.calls, 2);
    });

    testWidgets('a short background does not lock', (tester) async {
      final (clock, auth) = await pump(tester, enabled: true);
      await background(tester, clock, const Duration(seconds: 30));
      expect(find.byKey(const Key('biometric-lock')), findsNothing);
      expect(auth.calls, 0);
    });

    testWidgets('never locks when the setting is off', (tester) async {
      final (clock, auth) = await pump(tester, enabled: false);
      await background(tester, clock, const Duration(hours: 1));
      expect(find.byKey(const Key('biometric-lock')), findsNothing);
      expect(auth.calls, 0);
    });
  });

  testWidgets('app switcher cover hides content while inactive', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(const AppSwitcherPrivacy(child: Text('health data'))),
    );
    expect(find.byKey(const Key('app-switcher-cover')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('app-switcher-cover')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('app-switcher-cover')), findsNothing);
  });

  testWidgets('no cover while an app-opened system prompt is showing', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(const AppSwitcherPrivacy(child: Text('health data'))),
    );
    final prompt = Completer<void>();
    final done = SystemPrompt.guard(() => prompt.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('app-switcher-cover')), findsNothing);
    expect(find.text('health data'), findsOneWidget);
    prompt.complete();
    await done;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(SystemPrompt.active, isFalse);
  });
}
