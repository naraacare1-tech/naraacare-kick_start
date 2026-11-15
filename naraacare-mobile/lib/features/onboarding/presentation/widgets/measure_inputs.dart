import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/core/utils/units.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_wheel_picker.dart';

/// Two-way unit switch (cm | ft/in, kg | lb).
class UnitToggle extends StatelessWidget {
  const new({
    required this.metricLabel,
    required this.imperialLabel,
    required this.imperial,
    required this.onChanged,
    super.key,
  });

  final String metricLabel;
  final String imperialLabel;
  final bool imperial;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Center(
    child: SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, label: Text(metricLabel)),
        ButtonSegment(value: true, label: Text(imperialLabel)),
      ],
      selected: {imperial},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );
}

/// Height ruler/wheel (O2): whole cm 120-230, or feet + inches converted to
/// cm (stored metric, doc 06 section 1). Picker input only, no free text.
class HeightPicker extends StatelessWidget {
  const new({
    required this.heightCm,
    required this.feetInches,
    required this.onChanged,
    super.key,
    this.height = 200,
  });

  static const minCm = 120;
  static const maxCm = 230;

  final double heightCm;
  final bool feetInches;
  final ValueChanged<double> onChanged;

  /// Wheel height (smaller inside Edit Profile).
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!feetInches) {
      return NcWheelPicker<int>(
        values: [for (var cm = minCm; cm <= maxCm; cm++) cm],
        selected: heightCm.round().clamp(minCm, maxCm),
        height: height,
        labelOf: (cm) => '$cm ${l10n.unitCm}',
        onChanged: (cm) => onChanged(cm.toDouble()),
      );
    }
    final current = Units.cmToFeetInches(heightCm);
    double clampCm(int feet, int inches) =>
        Units.feetInchesToCm(feet, inches).clamp(minCm, maxCm).toDouble();
    return Row(
      children: [
        Expanded(
          child: NcWheelPicker<int>(
            values: const [3, 4, 5, 6, 7],
            selected: current.feet.clamp(3, 7),
            height: height,
            labelOf: (ft) => '$ft ft',
            onChanged: (ft) => onChanged(clampCm(ft, current.inches)),
          ),
        ),
        const SizedBox(width: NcSpace.cardGap),
        Expanded(
          child: NcWheelPicker<int>(
            values: [for (var i = 0; i < 12; i++) i],
            selected: current.inches,
            height: height,
            labelOf: (inch) => '$inch in',
            onChanged: (inch) => onChanged(clampCm(current.feet, inch)),
          ),
        ),
      ],
    );
  }
}

/// Weight entry in kg (30-250, 2 decimals) or lb (converted to kg before it
/// is sent). Digits and one decimal point only.
class WeightField extends StatelessWidget {
  const new({
    required this.controller,
    required this.pounds,
    required this.hint,
    super.key,
    this.onChanged,
    this.serverError,
  });

  static const minKg = 30.0;
  static const maxKg = 250.0;

  final TextEditingController controller;
  final bool pounds;
  final String hint;
  final ValueChanged<String>? onChanged;
  final String? serverError;

  static final Validator _kg = InputValidators.decimal(min: minKg, max: maxKg);
  static final Validator _lb = InputValidators.decimal(
    min: Units.kgToLb(minKg),
    max: Units.kgToLb(maxKg),
    decimals: 1,
  );

  /// The entered weight in kg, or null when invalid.
  static double? kgFrom(String text, {required bool pounds}) {
    final validator = pounds ? _lb : _kg;
    if (validator(text) != null) return null;
    final value = double.parse(InputValidators.normalise(text));
    final kg = pounds ? Units.lbToKg(value) : value;
    return kg.clamp(minKg, maxKg);
  }

  /// Display text for a stored kg value in the chosen unit.
  static String display(double? kg, {required bool pounds}) {
    if (kg == null) return '';
    final value = pounds ? Units.kgToLb(kg) : kg;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(pounds ? 1 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NcTextField(
      controller: controller,
      validator: pounds ? _lb : _kg,
      maxLength: 6,
      hint: hint,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [NcTextField.decimal],
      textAlign: TextAlign.center,
      prefixIcon: Icons.monitor_weight_outlined,
      helper: pounds ? l10n.unitLb : l10n.unitKg,
      serverError: serverError,
      onChanged: onChanged,
    );
  }
}
