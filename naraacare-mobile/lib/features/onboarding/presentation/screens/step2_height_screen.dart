import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/core/utils/units.dart';
import 'package:naraacare/features/onboarding/presentation/step_saver.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/measure_inputs.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';

/// O2 (Onboarding 2 cm / ft): height wheel with the cm <-> ft/in toggle.
class Step2HeightScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<Step2HeightScreen> createState() => _Step2State();
}

class _Step2State extends ConsumerState<Step2HeightScreen>
    with StepSaver<Step2HeightScreen> {
  @override
  int get step => 2;

  late double _cm = draft.heightCm ?? 160;
  late bool _feet = draft.feetInches;

  Future<void> _next() async {
    draft
      ..heightCm = _cm
      ..feetInches = _feet;
    await saveAndContinue({'height_cm': wireDecimal(_cm, 1)});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ftIn = Units.cmToFeetInches(_cm);
    return OnboardingScaffold(
      step: step,
      title: l10n.step2Title,
      why: l10n.step2Why,
      busy: busy,
      error: error,
      onBack: goBack,
      onNext: _next,
      child: Column(
        children: [
          UnitToggle(
            metricLabel: l10n.unitCm,
            imperialLabel: l10n.unitFtIn,
            imperial: _feet,
            onChanged: (v) => setState(() => _feet = v),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          Text(
            _feet
                ? l10n.feetInches(ftIn.feet, ftIn.inches)
                : '${_cm.round()} ${l10n.unitCm}',
            style: text.headlineMedium,
          ),
          const SizedBox(height: NcSpace.cardGap),
          HeightPicker(
            heightCm: _cm,
            feetInches: _feet,
            onChanged: (cm) => setState(() => _cm = cm),
          ),
        ],
      ),
    );
  }
}
