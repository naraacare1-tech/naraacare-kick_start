import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/secure_storage.dart';
import 'package:naraacare/core/utils/logger.dart';

/// Where the user is in the app's flow (doc 02 section 2.0).
enum AuthStatus {
  /// Splash: still checking stored tokens.
  unknown,

  /// First install: intro slides before Welcome (OQ-62).
  introNeeded,
  signedOut,

  /// Signed in, onboarding steps not finished (resume).
  onboarding,
  signedIn,
}

/// Session start-up and transitions. The router listens to it.
///
/// Start-up (A1 Splash): stored tokens -> silent refresh -> signed in or out.
/// Offline with stored tokens: the user stays signed in with the last known
/// onboarding state (offline-first); the refresh is retried on the next API
/// call. A refused refresh (revoked, reused, expired) signs the user out.
class AuthController extends ChangeNotifier {
  new({
    required this.storage,
    required this.session,
    required this.api,
    this.wipeLocalData,
    this.onSignedOut,
  }) {
    _ended = session.sessionEnded.listen((_) => unawaited(_afterSignOut()));
  }

  final SecureStorage storage;
  final SessionStore session;
  final ApiClient api;

  /// Removes the user's data from this phone on sign-out (S15).
  final Future<void> Function()? wipeLocalData;

  /// Resets all in-memory app state after sign-out (the app restarts from
  /// the splash with a fresh provider scope).
  final void Function()? onSignedOut;
  late final StreamSubscription<void> _ended;

  static const _onboardingDone = 'app.onboarding_complete';

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  void _set(AuthStatus status) {
    if (status == _status) return;
    _status = status;
    notifyListeners();
  }

  Future<void> start() async {
    final tokens = await session.tokens();
    if (tokens == null) {
      _set(
        await storage.introSeen()
            ? AuthStatus.signedOut
            : AuthStatus.introNeeded,
      );
      return;
    }
    try {
      final pair = await api.post(
        'auth/token/refresh',
        body: {
          'refresh_token': tokens.refreshToken,
          'installation_id': await storage.installationId(),
        },
        options: ApiClient.public,
      );
      await signedIn(pair! as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.isNetwork || e.code == ApiError.certificate) {
        log.info('session_start_offline', {'code': e.code});
        _set(
          await _onboardingComplete()
              ? AuthStatus.signedIn
              : AuthStatus.onboarding,
        );
        return;
      }
      await session.clear(notify: false);
      _set(AuthStatus.signedOut);
    }
  }

  String _onboardingEntry = Routes.onboarding;

  /// Where a user who still has onboarding to do lands after signing in.
  String get onboardingEntry => _onboardingEntry;

  /// The splash animation has played to the end: until then the router
  /// stays on the splash whatever the auth state (owner 2026-11-08).
  bool _splashDone = false;
  bool get splashDone => _splashDone;

  void finishSplash() {
    if (_splashDone) return;
    _splashDone = true;
    notifyListeners();
  }

  /// After sign-in, sign-up verification or a refresh: a TokenPair body.
  /// [verifiedEmail] shows A5 "Email Verified" before onboarding.
  Future<void> signedIn(
    Map<String, dynamic> pair, {
    bool verifiedEmail = false,
  }) async {
    await session.save(
      accessToken: pair['access_token'] as String,
      refreshToken: pair['refresh_token'] as String,
      accessExpiresInSeconds: pair['access_expires_in_s'] as int,
    );
    _onboardingEntry = verifiedEmail ? Routes.emailVerified : Routes.onboarding;
    final onboardingRequired = pair['onboarding_required'] == true;
    await _rememberOnboarding(!onboardingRequired);
    _set(onboardingRequired ? AuthStatus.onboarding : AuthStatus.signedIn);
  }

  Future<void> onboardingCompleted() async {
    await _rememberOnboarding(true);
    _set(AuthStatus.signedIn);
  }

  Future<void> introCompleted() async {
    await storage.markIntroSeen();
    if (_status == AuthStatus.introNeeded) _set(AuthStatus.signedOut);
  }

  /// Log Out (ST14): revokes the session on the server (best effort: offline
  /// or an already-revoked session still signs out locally), then forgets
  /// the tokens, the offline cache key and the onboarding flag.
  Future<void> signOut() async {
    try {
      // Stop pushes to this phone first (needs the still-valid session).
      await api.delete('devices/${await storage.installationId()}');
      await api.post('auth/logout');
    } on ApiError catch (e) {
      log.info('logout_server_failed', {'code': e.code});
    }
    await _rememberOnboarding(false);
    await signedOut();
  }

  /// Local sign-out only (the session already ended on the server).
  Future<void> signedOut() async {
    await session.clear(notify: false);
    await _afterSignOut();
  }

  Future<void> _afterSignOut() async {
    await wipeLocalData?.call();
    _set(AuthStatus.signedOut);
    onSignedOut?.call();
  }

  Future<bool> _onboardingComplete() async =>
      await storage.readFlag(_onboardingDone);

  Future<void> _rememberOnboarding(bool done) =>
      storage.writeFlag(_onboardingDone, value: done);

  @override
  void dispose() {
    unawaited(_ended.cancel());
    super.dispose();
  }
}
