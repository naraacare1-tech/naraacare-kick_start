import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:naraacare/core/config/flavor.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/network/connectivity.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/app_router.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/data/social_sign_in.dart';
import 'package:naraacare/features/home/presentation/home_screen.dart';
import 'package:naraacare/features/nutrition/presentation/screens/voice_barcode_screens.dart';

import 'harness.dart';

AppConfig testConfig([Flavor flavor = Flavor.dev]) => AppConfig(
  flavor: flavor,
  apiBaseUrl: Uri.parse('https://api.example/api/v1'),
  wsBaseUrl: Uri.parse('wss://api.example/api/v1/ws'),
  certPins: const [],
  googleServerClientId: 'x',
  termsUrl: Uri.parse('https://naraacare.app/terms'),
  privacyUrl: Uri.parse('https://naraacare.app/privacy'),
);

/// Connectivity without the platform plugin; tests flip [online].
class FakeConnectivity implements ConnectivityMonitor {
  final _changes = StreamController<bool>.broadcast();
  bool _online = true;

  bool get online => _online;
  set online(bool value) {
    _online = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get onlineChanges => _changes.stream;
}

/// Speech recognition without a microphone: [words] are "heard" on start.
class FakeVoiceRecognizer implements VoiceRecognizer {
  String words = 'do roti aur ek katori dal';
  bool available = true;

  @override
  Future<bool> start(
    void Function(String words, {required bool done}) onWords, {
    void Function()? onError,
  }) async {
    if (!available) return false;
    onWords(words, done: true);
    return true;
  }

  @override
  Future<void> stop() async {}
}

const testDbKey = 'k8Jt0r4Pz2mYxV9aQ1sB6nW3eL7cU5hD0fG2iK4oR8s=';

/// Google/Apple without the platform SDKs.
class FakeSocialSignIn implements SocialSignIn {
  @override
  bool appleAvailable = true;

  Future<GoogleCredential> Function() onGoogle = () async =>
      (idToken: 'google-id-token', nonce: 'raw-nonce-g');

  Future<AppleCredential> Function() onApple = () async => (
    identityToken: 'apple-identity-token',
    authorizationCode: 'apple-code',
    nonce: 'raw-nonce-a',
  );

  @override
  Future<GoogleCredential> google() => onGoogle();

  @override
  Future<AppleCredential> apple() => onApple();
}

/// The whole app (router + screens) against the fake API, with the same
/// auth controller for the router and the screens (as in the app), an
/// in-memory encrypted DB and a phone-sized screen (390 x 844).
class AppHarness extends Harness {
  final social = FakeSocialSignIn();
  final connectivity = FakeConnectivity();
  final voice = FakeVoiceRecognizer();
  late AppDatabase db;
  late final AuthController auth = authController();
  late GoRouter router;
  late BuildContext _context;

  String get location => router.state.uri.path;

  AppLocalizations get l10n => AppLocalizations.of(_context);

  Future<void> pump(WidgetTester tester, {bool introSeen = true}) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    HomeScreen.usernameOffered = false;
    if (introSeen) await storage.markIntroSeen();
    db = AppDatabase.memory(testDbKey);
    addTearDown(db.close);
    router = buildRouter(auth);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testConfig()),
          keyValueStoreProvider.overrideWithValue(keys),
          apiClientProvider.overrideWithValue(api),
          authControllerProvider.overrideWithValue(auth),
          databaseProvider.overrideWithValue(db),
          socialSignInProvider.overrideWithValue(social),
          connectivityProvider.overrideWithValue(connectivity),
          voiceRecognizerProvider.overrideWithValue(voice),
          // No camera in tests: the scanner area is a placeholder.
          scannerBuilderProvider.overrideWithValue(
            (context, onCode) => const SizedBox.shrink(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          localizationsDelegates: localizations,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            _context = context;
            return child ?? const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String location, {Object? extra}) async {
    router.go(location, extra: extra);
    await tester.pumpAndSettle();
  }

  /// Taps a button/link by its text (scrolling it into view first).
  Future<void> tapText(WidgetTester tester, String text) async {
    // Lazy lists build off-screen rows only once scrolled to. Drag from the
    // left edge (page padding) so pickers in the page don't take the drag.
    for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(6, 600), const Offset(0, -300));
      await tester.pump();
    }
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Types into the text field labelled or hinted with [label].
  Future<void> type(WidgetTester tester, String label, String value) async {
    // The label/hint inside a text field (not an app bar title with the
    // same words).
    final fields = find.ancestor(
      of: find.descendant(
        of: find.byType(TextFormField),
        matching: find.text(label),
      ),
      matching: find.byType(TextFormField),
    );
    // Lazy lists drop rows scrolled away: scroll back up to find it.
    for (var i = 0; i < 40 && fields.evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(6, 300), const Offset(0, 300));
      await tester.pump();
    }
    expect(fields, findsWidgets, reason: 'no field "$label" at $location');
    final field = fields.first;
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }
}

/// GET /reference/bootstrap (the parts the S07 screens use).
const referenceBootstrap = <String, Object>{
  'calc_version': 'v1',
  'activity_levels': [
    {
      'code': 'sedentary',
      'label': 'Sedentary',
      'onboarding_label': 'Mostly sitting',
    },
    {
      'code': 'lightly_active',
      'label': 'Lightly active',
      'onboarding_label': 'Exercise 1-2 days/week',
    },
    {
      'code': 'moderately_active',
      'label': 'Moderately active',
      'onboarding_label': 'Active (Exercise 3-5 days/week)',
    },
    {
      'code': 'very_active',
      'label': 'Very active',
      'onboarding_label': 'Exercise 6-7 days/week',
    },
  ],
  'body_types': [
    {'code': 'ectomorph', 'label': 'Ectomorph'},
    {'code': 'mesomorph', 'label': 'Mesomorph'},
    {'code': 'endomorph', 'label': 'Endomorph'},
  ],
  'weight_goals': [
    {'code': 'moderate_loss', 'label': 'Moderate Loss'},
    {'code': 'mild_loss', 'label': 'Mild Loss'},
    {'code': 'maintain', 'label': 'Maintain'},
    {'code': 'mild_gain', 'label': 'Mild Gain'},
  ],
  'medical_conditions': [
    {'code': 'diabetes_t2', 'label': 'Type 2 diabetes', 'kind': 'condition'},
    {'code': 'hypertension', 'label': 'Hypertension', 'kind': 'condition'},
    {'code': 'peanut_allergy', 'label': 'Peanut allergy', 'kind': 'allergy'},
  ],
};

const policies = <String, Object>{
  'policies': [
    {
      'type': 'terms',
      'version': '2026-10',
      'url': 'https://naraacare.app/terms',
      'published_at': null,
    },
    {
      'type': 'privacy',
      'version': '2026-10b',
      'url': 'https://naraacare.app/privacy',
      'published_at': null,
    },
  ],
};

Map<String, Object?> profileJson({
  String? fullName = 'Priya Sharma',
  String? sex = 'female',
  String? bodyType = 'mesomorph',
}) => {
  'biological_sex': sex,
  'avatar_code': sex == null ? null : '${sex}_${bodyType ?? 'mesomorph'}',
  'full_name': fullName,
  'age_years': 28,
  'height_cm': '165.0',
  'weight_kg': '62.00',
  'target_weight_kg': '58.00',
  'weight_goal': 'mild_loss',
  'activity_level': 'moderately_active',
  'body_type': bodyType,
  'medical_condition_codes': <String>[],
};

Map<String, Object?> meJson({String? username = 'priya.s'}) => {
  'user_id': '0190f5d2-3c4b-7a1e-9f00-000000000001',
  'email': 'priya@example.com',
  'role': 'user',
  'tier': 'standard',
  'username': username,
  'onboarding': {'current_step': 6, 'completed': true},
  'profile': profileJson(),
  'settings': {
    'height_unit': 'cm',
    'weight_unit': 'kg',
    'temperature_unit': 'c',
    'timezone': 'Asia/Kolkata',
    'locale': 'en-IN',
    'sleep_start_local': '22:30:00',
    'wake_local': '06:30:00',
    'sleep_goal_min': 480,
    'biometric_lock': false,
  },
  'counts': {
    'connections': 0,
    'circles': 0,
    'current_streak': 0,
    'longest_streak': 0,
  },
};

const goalOptions = <String, Object>{
  'bmi': '22.8',
  'category': 'normal',
  'allowed_goals': ['mild_loss', 'maintain', 'mild_gain'],
  'healthy_weight_range_kg': [55, 68],
};

Map<String, Object> apiError(
  String code, [
  Map<String, Object> extra = const {},
]) => {
  'error': {'code': code, ...extra},
};
