import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:naraacare/core/security/system_prompt.dart';

/// Biometric / device-passcode check (doc 07 SEC-5.6). The app locks itself
/// when it returns from more than [BiometricPolicy.lockAfter] in the
/// background and the user turned the lock on (off by default).
abstract interface class Authenticator {
  Future<bool> authenticate(String reason);
}

class PlatformAuthenticator implements Authenticator {
  new([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Biometrics with the device passcode as the fallback.
      return await SystemPrompt.guard(
        () => _auth.authenticate(localizedReason: reason),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

abstract final class BiometricPolicy {
  static const lockAfter = Duration(seconds: 60);

  /// Whether returning to the foreground now needs authentication.
  static bool shouldLock({
    required bool enabled,
    required DateTime? backgroundedAt,
    required DateTime now,
  }) =>
      enabled &&
      backgroundedAt != null &&
      now.difference(backgroundedAt) > lockAfter;
}
