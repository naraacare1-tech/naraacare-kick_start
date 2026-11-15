import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:naraacare/core/config/flavor.dart';

const _pin = 'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

Map<String, String> _valid(Flavor flavor) => {
  'ENV_NAME': flavor.name,
  'API_BASE_URL': 'https://api.${flavor.name}.naraacare.app/api/v1',
  'WS_BASE_URL': 'wss://api.${flavor.name}.naraacare.app/api/v1/ws',
  'CERT_PINS': '$_pin,$_pin',
  'GOOGLE_SERVER_CLIENT_ID': 'x.apps.googleusercontent.com',
  'TERMS_URL': 'https://naraacare.app/terms',
  'PRIVACY_URL': 'https://naraacare.app/privacy',
};

Matcher _problem(String text) => isA<AppConfigException>().having(
  (e) => e.problems.join('|'),
  'problems',
  contains(text),
);

void main() {
  group('AppConfig.parse', () {
    test('accepts a valid prod configuration', () {
      final config = AppConfig.parse(Flavor.prod, _valid(Flavor.prod));
      expect(config.isProduction, isTrue);
      expect(config.apiBaseUrl.scheme, 'https');
      expect(config.googleServerClientId, 'x.apps.googleusercontent.com');
    });

    test('rejects http API outside dev', () {
      final raw = _valid(Flavor.staging)
        ..['API_BASE_URL'] = 'http://api.staging.naraacare.app/api/v1';
      expect(
        () => AppConfig.parse(Flavor.staging, raw),
        throwsA(_problem('API_BASE_URL must use https')),
      );
    });

    test('allows http only to local hosts in dev', () {
      final raw = _valid(Flavor.dev)
        ..['API_BASE_URL'] = 'http://10.0.2.2:8000/api/v1'
        ..['WS_BASE_URL'] = 'ws://10.0.2.2:8000/api/v1/ws'
        ..['CERT_PINS'] = '';
      expect(AppConfig.parse(Flavor.dev, raw).certPins, isEmpty);

      raw['API_BASE_URL'] = 'http://evil.example/api/v1';
      expect(
        () => AppConfig.parse(Flavor.dev, raw),
        throwsA(_problem('API_BASE_URL must use https')),
      );
    });

    test('requires certificate pins outside dev', () {
      final raw = _valid(Flavor.prod)..['CERT_PINS'] = '';
      expect(
        () => AppConfig.parse(Flavor.prod, raw),
        throwsA(_problem('CERT_PINS is required outside dev')),
      );
    });

    test('rejects malformed pins', () {
      final raw = _valid(Flavor.prod)..['CERT_PINS'] = 'md5/abc';
      expect(
        () => AppConfig.parse(Flavor.prod, raw),
        throwsA(_problem('sha256/<base64>')),
      );
    });

    test('rejects an env file built for another flavor', () {
      expect(
        () => AppConfig.parse(Flavor.prod, _valid(Flavor.dev)),
        throwsA(_problem('ENV_NAME must be "prod"')),
      );
    });

    test('lists keys, never values, in the error', () {
      final raw = _valid(Flavor.prod)
        ..['API_BASE_URL'] = 'http://secret-host.example'
        ..['GOOGLE_SERVER_CLIENT_ID'] = '';
      try {
        AppConfig.parse(Flavor.prod, raw);
        fail('expected AppConfigException');
      } on AppConfigException catch (e) {
        expect(e.toString(), isNot(contains('secret-host')));
        expect(e.problems, hasLength(2));
      }
    });
  });

  group('AppConfig.fromEnvironment', () {
    const envName = String.fromEnvironment('ENV_NAME');

    test(
      'reads values from --dart-define-from-file=env/test.env',
      () {
        final config = AppConfig.fromEnvironment(Flavor.dev);
        expect(config.apiBaseUrl.toString(), 'http://10.0.2.2:8000/api/v1');
        expect(
          config.googleServerClientId,
          'dummy-web.apps.googleusercontent.com',
        );
      },
      skip: envName.isEmpty
          ? 'run with --dart-define-from-file=env/test.env (CI does)'
          : false,
    );
  });
}
