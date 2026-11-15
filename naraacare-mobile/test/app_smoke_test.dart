import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/app.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:naraacare/core/config/flavor.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/network/connectivity.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/biometric_gate.dart';
import 'package:naraacare/core/security/root_check.dart';

import 'helpers/harness.dart';

AppConfig _config(Flavor flavor) => AppConfig(
  flavor: flavor,
  apiBaseUrl: Uri.parse('https://api.example/api/v1'),
  wsBaseUrl: Uri.parse('wss://api.example/api/v1/ws'),
  certPins: const [],
  googleServerClientId: 'x',
  termsUrl: Uri.parse('https://naraacare.app/terms'),
  privacyUrl: Uri.parse('https://naraacare.app/privacy'),
);

class _Connectivity implements ConnectivityMonitor {
  new({required this.online});

  final bool online;

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onlineChanges => const Stream.empty();
}

class _RootCheck implements RootCheck {
  const new({required this.compromised});

  final bool compromised;

  @override
  Future<bool> isCompromised() async => compromised;
}

class _Authenticator implements Authenticator {
  @override
  Future<bool> authenticate(String reason) async => true;
}

Future<Harness> _pump(
  WidgetTester tester,
  Flavor flavor, {
  bool online = true,
  bool compromised = false,
}) async {
  final harness = Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(_config(flavor)),
        keyValueStoreProvider.overrideWithValue(harness.keys),
        apiClientProvider.overrideWithValue(harness.api),
        connectivityProvider.overrideWithValue(_Connectivity(online: online)),
        rootCheckProvider.overrideWithValue(
          _RootCheck(compromised: compromised),
        ),
        authenticatorProvider.overrideWithValue(_Authenticator()),
      ],
      child: const NaraaCareApp(),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  for (final flavor in [Flavor.dev, Flavor.staging]) {
    testWidgets('${flavor.name} build shows the environment ribbon', (
      tester,
    ) async {
      await _pump(tester, flavor);
      expect(find.byType(Banner), findsOneWidget);
    });
  }

  testWidgets('prod build has no ribbon', (tester) async {
    await _pump(tester, Flavor.prod);
    expect(find.byType(Banner), findsNothing);
  });

  testWidgets('first launch goes from splash to the intro slides', (
    tester,
  ) async {
    await _pump(tester, Flavor.prod);
    final context = tester.element(find.byType(Navigator).first);
    final router = ProviderScope.containerOf(context).read(routerProvider);
    expect(router.state.uri.path, Routes.intro);
  });

  testWidgets('offline shows the banner; online does not', (tester) async {
    await _pump(tester, Flavor.prod, online: false);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    await _pump(tester, Flavor.prod);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
  });

  testWidgets('a rooted device gets a warning but keeps working', (
    tester,
  ) async {
    await _pump(tester, Flavor.prod, compromised: true);
    expect(find.byKey(const Key('rooted-warning')), findsOneWidget);
    await _pump(tester, Flavor.prod);
    expect(find.byKey(const Key('rooted-warning')), findsNothing);
  });
}
