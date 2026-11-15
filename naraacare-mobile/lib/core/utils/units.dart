/// Display-only unit conversion (doc 06 section 1). Values are stored and sent
/// in metric; conversions happen only when showing or reading user input.
abstract final class Units {
  static const _cmPerInch = 2.54;
  static const _kgPerLb = 0.45359237;

  static ({int feet, int inches}) cmToFeetInches(double cm) {
    final totalInches = (cm / _cmPerInch).round();
    return (feet: totalInches ~/ 12, inches: totalInches % 12);
  }

  static double feetInchesToCm(int feet, int inches) =>
      _round((feet * 12 + inches) * _cmPerInch, 1);

  static double kgToLb(double kg) => _round(kg / _kgPerLb, 1);

  static double lbToKg(double lb) => _round(lb * _kgPerLb, 2);

  static double celsiusToFahrenheit(double c) => _round(c * 9 / 5 + 32, 1);

  static double fahrenheitToCelsius(double f) => _round((f - 32) * 5 / 9, 1);

  static double _round(double value, int places) {
    final factor = places == 1 ? 10 : 100;
    return (value * factor).roundToDouble() / factor;
  }
}
