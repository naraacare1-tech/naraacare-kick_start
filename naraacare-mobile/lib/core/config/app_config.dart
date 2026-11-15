import 'package:flutter/foundation.dart';
import 'package:naraacare/core/config/flavor.dart';

/// Thrown at startup when the compile-time configuration is unsafe or
/// incomplete. The message lists keys only, never values.
class AppConfigException implements Exception {
  const new(this.problems);

  final List<String> problems;

  @override
  String toString() => 'Invalid app configuration:\n- ${problems.join('\n- ')}';
}

/// Non-secret configuration injected per flavor with
/// `--dart-define-from-file=env/<flavor>.env` (doc 08 §4).
/// No secrets may ever be added here: everything in the binary is public.
@immutable
class AppConfig {
  const new({
    required this.flavor,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.certPins,
    required this.googleServerClientId,
    required this.termsUrl,
    required this.privacyUrl,
  });

  /// Reads the compile-time defines. `String.fromEnvironment` needs literal
  /// keys, so each key is listed explicitly.
  factory fromEnvironment(Flavor flavor) => AppConfig.parse(flavor, const {
    'ENV_NAME': String.fromEnvironment('ENV_NAME'),
    'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
    'WS_BASE_URL': String.fromEnvironment('WS_BASE_URL'),
    'CERT_PINS': String.fromEnvironment('CERT_PINS'),
    'GOOGLE_SERVER_CLIENT_ID': String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    'TERMS_URL': String.fromEnvironment('TERMS_URL'),
    'PRIVACY_URL': String.fromEnvironment('PRIVACY_URL'),
  });

  /// Validates raw values. Pure function so it can be unit-tested.
  factory parse(Flavor flavor, Map<String, String> raw) {
    final problems = <String>[];
    String value(String key) => (raw[key] ?? '').trim();

    Uri? uri(String key, Set<String> schemes) {
      final parsed = Uri.tryParse(value(key));
      if (parsed == null || !parsed.hasAuthority) {
        problems.add('$key must be an absolute URL');
        return null;
      }
      final localDev =
          flavor == Flavor.dev && _localHosts.contains(parsed.host);
      if (!schemes.contains(parsed.scheme) && !localDev) {
        problems.add('$key must use ${schemes.join('/')}');
      }
      return parsed;
    }

    if (Flavor.tryParse(value('ENV_NAME')) != flavor) {
      problems.add('ENV_NAME must be "${flavor.name}" for this entry point');
    }
    final api = uri('API_BASE_URL', {'https'});
    final ws = uri('WS_BASE_URL', {'wss'});
    final terms = uri('TERMS_URL', {'https'});
    final privacy = uri('PRIVACY_URL', {'https'});

    final pins = _list(value('CERT_PINS'));
    if (flavor != Flavor.dev && pins.isEmpty) {
      problems.add('CERT_PINS is required outside dev');
    }
    for (final pin in pins) {
      if (!_pinPattern.hasMatch(pin)) {
        problems.add('CERT_PINS entries must look like sha256/<base64>');
        break;
      }
    }

    if (value('GOOGLE_SERVER_CLIENT_ID').isEmpty) {
      problems.add('GOOGLE_SERVER_CLIENT_ID is required');
    }

    if (problems.isNotEmpty) throw AppConfigException(problems);

    return AppConfig(
      flavor: flavor,
      apiBaseUrl: api!,
      wsBaseUrl: ws!,
      certPins: pins,
      googleServerClientId: value('GOOGLE_SERVER_CLIENT_ID'),
      termsUrl: terms!,
      privacyUrl: privacy!,
    );
  }

  static const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
  static final _pinPattern = RegExp(r'^sha256/[A-Za-z0-9+/]{43}=$');

  static List<String> _list(String csv) => List.unmodifiable(
    csv.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
  );

  final Flavor flavor;
  final Uri apiBaseUrl;
  final Uri wsBaseUrl;
  final List<String> certPins;
  final String googleServerClientId;
  final Uri termsUrl;
  final Uri privacyUrl;

  bool get isProduction => flavor == Flavor.prod;
}
