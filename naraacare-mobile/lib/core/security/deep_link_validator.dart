import 'package:flutter/foundation.dart';

/// A deep link the app accepts (doc 07 SEC-5.8). Anything else is ignored.
@immutable
sealed class DeepLink {
  const new();
}

/// `https://<REFERRAL_LINK_DOMAIN>/invite/<code>` - referral / invite code.
class InviteLink extends DeepLink {
  const new(this.code);

  final String code;
}

/// `https://<REFERRAL_LINK_DOMAIN>/circle/<token>` - care circle invitation.
class CircleLink extends DeepLink {
  const new(this.token);

  final String token;
}

/// Validates incoming links before the router uses them: https only, our own
/// domain only, exactly two path segments, and parameters that pass the same
/// rules as the API (no query strings or fragments are read). The server
/// resolves codes and tokens; the app only forwards them.
class DeepLinkValidator {
  const new(this.domain);

  final String domain;

  static final _code = RegExp(r'^[A-Z0-9]{6,12}$');
  static final _token = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  /// Referral / invite code rules (SafeReferralCode, upper case).
  static bool isInviteCode(String value) => _code.hasMatch(value);

  /// Circle invitation token rules (opaque, URL-safe).
  static bool isCircleToken(String value) => _token.hasMatch(value);

  DeepLink? parse(Uri uri) {
    final secureOurs =
        uri.scheme == 'https' &&
        uri.host == domain &&
        !uri.hasPort &&
        uri.userInfo.isEmpty;
    if (!secureOurs || uri.pathSegments.length != 2) return null;
    final [kind, value] = uri.pathSegments;
    return switch (kind) {
      'invite' when isInviteCode(value.toUpperCase()) => InviteLink(
        value.toUpperCase(),
      ),
      'circle' when isCircleToken(value) => CircleLink(value),
      _ => null,
    };
  }

  /// Route path for an accepted link (the router re-checks it).
  static String routeFor(DeepLink link) => switch (link) {
    InviteLink(:final code) => '/invite/$code',
    CircleLink(:final token) => '/circle/$token',
  };
}
