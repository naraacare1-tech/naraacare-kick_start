import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/utils/logger.dart';
import 'package:naraacare/core/utils/units.dart';

void main() {
  group('AppLogger', () {
    test('writes event lines when enabled', () {
      final lines = <String>[];
      AppLogger(sink: lines.add).info('sync_flush', {'sent': 3});
      expect(lines, ['[INFO] sync_flush {sent: 3}']);
    });

    test('is a no-op when disabled (release builds)', () {
      final lines = <String>[];
      AppLogger(enabled: false, sink: lines.add)
        ..info('a')
        ..warning('b');
      expect(lines, isEmpty);
    });
  });

  group('Units', () {
    test('height', () {
      expect(Units.cmToFeetInches(170), (feet: 5, inches: 7));
      expect(Units.feetInchesToCm(5, 7), 170.2);
    });

    test('weight', () {
      expect(Units.kgToLb(70), 154.3);
      expect(Units.lbToKg(154.3), 69.99);
    });

    test('temperature', () {
      expect(Units.celsiusToFahrenheit(37), 98.6);
      expect(Units.fahrenheitToCelsius(98.6), 37);
    });
  });
}
