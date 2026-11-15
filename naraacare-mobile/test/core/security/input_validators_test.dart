import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/security/reject_patterns.dart';

import '../../security/payloads.dart';

/// Every text validator of the app, as used by the forms.
final Map<String, Validator> textValidators = {
  'name': InputValidators.name,
  'username': InputValidators.username,
  'email': InputValidators.email,
  'password': InputValidators.password,
  'passwordLogin': InputValidators.passwordLogin,
  'otp': InputValidators.otp,
  'shortText': InputValidators.shortText(max: 120),
  'freeText': InputValidators.freeText(max: 2000),
  'chatMessage': InputValidators.chatMessage(),
  'search': InputValidators.search,
  'usernameSearch': InputValidators.usernameSearch,
  'barcodeOrSearch': InputValidators.barcodeOrSearch,
  'integer': InputValidators.integer(min: 0, max: 100000),
  'decimal': InputValidators.decimal(min: 0, max: 100000),
};

/// Backend Safe* type -> the app validator for the same field.
final Map<String, Validator> byBackendType = {
  'SafeName': InputValidators.name,
  'SafeShortText120': InputValidators.shortText(max: 120),
  'SafeText500': InputValidators.freeText(max: 500),
  'SafeChatMessage': InputValidators.chatMessage(),
  'SafeSearchQuery': InputValidators.search,
  'SafeUsername': InputValidators.username,
  'SafeEmail': InputValidators.email,
  'SafePassword': InputValidators.passwordLogin,
  'SafeNewPassword': InputValidators.password,
  'SafeOtp': InputValidators.otp,
  'SafeBarcode': InputValidators.barcodeOrSearch,
};

Map<String, List<String>> loadVectors() {
  final file = File('test/core/security/vectors.json');
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (doc['accept'] as Map<String, dynamic>).map(
    (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()),
  );
}

void main() {
  final payloads = loadPayloads();

  group('payload list', () {
    for (final entry in textValidators.entries) {
      test('${entry.key} rejects every payload', () {
        final accepted = [
          for (final p in payloads)
            if (entry.value(p) == null) p,
        ];
        expect(accepted, isEmpty, reason: '${accepted.length} accepted');
      });
    }
  });

  group('legitimate input shared with the backend', () {
    final vectors = loadVectors();
    for (final entry in byBackendType.entries) {
      test('${entry.key} samples are accepted', () {
        final samples = vectors[entry.key]!;
        expect(samples, isNotEmpty);
        final refused = {
          for (final s in samples)
            if (entry.value(s) != null) s: entry.value(s),
        };
        expect(refused, isEmpty);
      });
    }

    test('more than 100 shared samples', () {
      final count = byBackendType.keys
          .map((k) => vectors[k]!.length)
          .reduce((a, b) => a + b);
      expect(count, greaterThanOrEqualTo(100));
    });
  });

  group('per-type rules', () {
    test('names need a letter and refuse digits', () {
      expect(InputValidators.name('Priya2'), ValidationError.format);
      expect(InputValidators.name("D'Souza-Rao"), isNull);
      expect(InputValidators.name('   '), ValidationError.required);
      expect(InputValidators.name('a' * 101), ValidationError.tooLong);
    });

    test('usernames are compared in lower case without repeats', () {
      expect(InputValidators.username('Priya.S'), isNull);
      expect(InputValidators.username('pr..iya'), ValidationError.format);
      expect(InputValidators.username('ab'), ValidationError.tooShort);
      expect(InputValidators.username('_priya'), ValidationError.format);
    });

    test('new passwords need upper case and a digit', () {
      expect(
        InputValidators.password('lowercase1'),
        ValidationError.weakPassword,
      );
      expect(InputValidators.password('Short1'), ValidationError.tooShort);
      expect(InputValidators.password('Correct1Horse'), isNull);
      expect(InputValidators.passwordLogin('lowercase'), isNull);
    });

    test('confirmation compares with the current password', () {
      var original = 'Correct1Horse';
      final confirm = InputValidators.confirmPassword(() => original);
      expect(confirm('Correct1Horse'), isNull);
      original = 'Changed1Horse';
      expect(confirm('Correct1Horse'), ValidationError.mismatch);
    });

    test('OTP accepts full-width digits after NFKC', () {
      expect(InputValidators.otp('123456'), isNull);
      final fullWidth = String.fromCharCodes(
        '123456'.codeUnits.map((c) => c - 0x30 + 0xFF10),
      );
      expect(InputValidators.otp(fullWidth), isNull);
      expect(InputValidators.otp('12345'), ValidationError.tooShort);
    });

    test('numbers: ranges and decimal places', () {
      final age = InputValidators.integer(min: 18, max: 100);
      expect(age('17'), ValidationError.outOfRange);
      expect(age('18'), isNull);
      expect(age('-5'), ValidationError.format);
      final weight = InputValidators.decimal(min: 30, max: 250);
      expect(weight('72.55'), isNull);
      expect(weight('72.555'), ValidationError.format);
      expect(weight('251'), ValidationError.outOfRange);
    });

    test('barcode digits need a valid check digit', () {
      expect(InputValidators.barcodeOrSearch('8901058000290'), isNull);
      expect(
        InputValidators.barcodeOrSearch('8901058000291'),
        ValidationError.format,
      );
      expect(InputValidators.barcodeOrSearch('moong dal'), isNull);
    });

    test('emoji joiners are allowed only inside emoji, in chat only', () {
      final zwj = String.fromCharCode(RejectPatterns.zwj);
      final family = '\u{1F468}$zwj\u{1F469}$zwj\u{1F467}';
      expect(InputValidators.chatMessage()('Great job $family'), isNull);
      expect(
        InputValidators.chatMessage()('hid${zwj}den'),
        ValidationError.unsafe,
      );
      expect(InputValidators.shortText(max: 60)('Great $family'), isNotNull);
    });

    test('legacy entities without a semicolon are caught (like the API)', () {
      expect(
        InputValidators.shortText(max: 60)('&ltscript&gt'),
        ValidationError.unsafe,
      );
    });

    test('normalise trims and folds', () {
      expect(InputValidators.normalise('  Priya  '), 'Priya');
      expect(InputValidators.normalise('  pass  ', trim: false), '  pass  ');
    });
  });
}
