import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:naraacare/core/config/flavor.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/network/pinning.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/security/secure_storage.dart';

const fixtures = 'test/fixtures/tls';
const wrongPin = 'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

Uint8List pemToDer(String pem) => base64.decode(
  pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join(),
);

AppConfig config(List<String> pins, int port) => AppConfig(
  flavor: Flavor.staging,
  apiBaseUrl: Uri.parse('https://localhost:$port/api/v1'),
  wsBaseUrl: Uri.parse('wss://localhost:$port/api/v1/ws'),
  certPins: pins,
  googleServerClientId: 'x',
  termsUrl: Uri.parse('https://naraacare.app/terms'),
  privacyUrl: Uri.parse('https://naraacare.app/privacy'),
);

void main() {
  final certPem = File('$fixtures/server.pem').readAsStringSync();
  final expectedPin = File('$fixtures/pin.txt').readAsStringSync().trim();

  test('SPKI pin matches the independently computed value', () {
    expect(CertificatePinning.spkiPin(pemToDer(certPem)), expectedPin);
  });

  test('malformed certificates never pin', () {
    expect(
      () => CertificatePinning.subjectPublicKeyInfo(Uint8List.fromList([1])),
      throwsFormatException,
    );
  });

  group('against a local TLS server', () {
    late HttpServer server;

    setUp(() async {
      final context = SecurityContext()
        ..useCertificateChain('$fixtures/server.pem')
        ..usePrivateKey('$fixtures/server.key');
      server = await HttpServer.bindSecure('localhost', 0, context)
        ..listen((request) {
          request.response
            ..headers.contentType = ContentType.json
            ..write('{"status":"ok"}')
            ..close().ignore();
        });
    });

    tearDown(() => server.close(force: true));

    // The test server's certificate is trusted as a root so that ordinary
    // chain validation passes; the pin is then the deciding check.
    HttpClient trusting() => HttpClient(
      context: SecurityContext()
        ..setTrustedCertificates('$fixtures/server.pem'),
    );

    ApiClient client(List<String> pins) => ApiClient.create(
      config: config(pins, server.port),
      session: SessionStore(SecureStorage(MemoryKeyValueStore())),
      storage: SecureStorage(MemoryKeyValueStore()),
      httpClientFactory: trusting,
    );

    test('the right pin connects', () async {
      final body = await client([wrongPin, expectedPin]).get('health/live');
      expect(body, {'status': 'ok'});
    });

    test('a wrong pin refuses the connection (no request is made)', () async {
      await expectLater(
        client([wrongPin]).get('health/live'),
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', ApiError.certificate),
        ),
      );
    });
  });
}
