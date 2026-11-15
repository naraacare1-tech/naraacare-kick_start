import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// What a provider gives back, ready for POST /auth/oauth/{google,apple}.
/// `nonce` is the RAW nonce: the provider only ever saw its SHA-256 (hex),
/// and the API checks the token's nonce claim against that hash (SEC-1.4).
typedef GoogleCredential = ({String idToken, String nonce});
typedef AppleCredential = ({
  String identityToken,
  String? authorizationCode,
  String nonce,
});

/// The user closed the provider's sheet: no error is shown.
class SocialSignInCancelled implements Exception {
  const new();
}

/// The provider could not be reached or returned no token (A11 banners).
class SocialSignInFailed implements Exception {
  const new();
}

abstract interface class SocialSignIn {
  bool get appleAvailable;
  Future<GoogleCredential> google();
  Future<AppleCredential> apple();
}

class PlatformSocialSignIn implements SocialSignIn {
  new(this.config, {Random? random}) : _random = random ?? Random.secure();

  final AppConfig config;
  final Random _random;
  bool _googleReady = false;

  /// 32 random bytes, base64url; never logged.
  String _rawNonce() => base64Url
      .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static String _sha256Hex(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  /// iOS only for now: on Android Apple's web flow needs a callback route on
  /// the API (APPLE_REDIRECT_URI) that does not exist yet (S07 deviation).
  @override
  bool get appleAvailable => Platform.isIOS;

  @override
  Future<GoogleCredential> google() async {
    final nonce = _rawNonce();
    final google = GoogleSignIn.instance;
    try {
      // The nonce is fixed at initialisation; re-initialise for every attempt
      // so each sign-in carries a fresh one.
      if (_googleReady) await google.signOut();
      await google.initialize(
        serverClientId: config.googleServerClientId,
        nonce: _sha256Hex(nonce),
      );
      _googleReady = true;
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const SocialSignInFailed();
      return (idToken: idToken, nonce: nonce);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw const SocialSignInFailed();
    } on PlatformException {
      throw const SocialSignInFailed();
    }
  }

  @override
  Future<AppleCredential> apple() async {
    final nonce = _rawNonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: _sha256Hex(nonce),
      );
      final token = credential.identityToken;
      if (token == null) throw const SocialSignInFailed();
      return (
        identityToken: token,
        authorizationCode: credential.authorizationCode,
        nonce: nonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw const SocialSignInFailed();
    } on SignInWithAppleException {
      throw const SocialSignInFailed();
    } on PlatformException {
      throw const SocialSignInFailed();
    }
  }
}
