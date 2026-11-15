import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/step_saver.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/condition_search.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/measure_inputs.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// O4 (Onboarding 4): target weight with the healthy-BMI range hint (and a
/// below/above warning), then medical conditions.
class Step4TargetConditionsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<Step4TargetConditionsScreen> createState() => _Step4State();
}

class _Step4State extends ConsumerState<Step4TargetConditionsScreen>
    with StepSaver<Step4TargetConditionsScreen> {
  @override
  int get step => 4;

  final _form = GlobalKey<FormState>();
  late bool _pounds = draft.pounds;
  late final _target = TextEditingController(
    text: WeightField.display(draft.targetWeightKg, pounds: draft.pounds),
  );
  late List<String> _conditions = [...draft.conditions];
  (int, int)? _range;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRange());
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _loadRange() async {
    try {
      final options = await ref.read(profileApiProvider).goalOptions();
      if (mounted) {
        setState(() => _range = (options.healthyMinKg, options.healthyMaxKg));
      }
    } on ApiError {
      // The hint is optional.
    }
  }

  double? get _kg => WeightField.kgFrom(_target.text, pounds: _pounds);

  Future<void> _next() async {
    final kg = _kg;
    if (!_form.currentState!.validate() || kg == null) return;
    draft
      ..targetWeightKg = kg
      ..pounds = _pounds
      ..conditions = _conditions;
    await saveAndContinue({
      'target_weight_kg': wireDecimal(kg, 2),
      'medical_condition_codes': _conditions,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final kg = _kg;
    final range = _range;
    final inside = range == null || kg == null
        ? null
        : kg >= range.$1 && kg <= range.$2;
    return OnboardingScaffold(
      step: step,
      title: l10n.step4Title,
      why: l10n.step4Why,
      busy: busy,
      error: error,
      onBack: goBack,
      onNext: _next,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UnitToggle(
              metricLabel: l10n.unitKg,
              imperialLabel: l10n.unitLb,
              imperial: _pounds,
              onChanged: (pounds) => setState(() {
                _target.text = WeightField.display(_kg, pounds: pounds);
                _pounds = pounds;
              }),
            ),
            const SizedBox(height: NcSpace.cardGap),
            WeightField(
              controller: _target,
              pounds: _pounds,
              hint: l10n.targetHint,
              onChanged: (_) => setState(() {}),
            ),
            if (range != null) ...[
              const SizedBox(height: NcSpace.inputGap),
              Text(
                inside ?? true
                    ? l10n.healthyRange(range.$1, range.$2)
                    : l10n.outsideRange(range.$1, range.$2),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: inside ?? true ? nc.success : nc.error),
              ),
            ],
            const SizedBox(height: NcSpace.sectionGap),
            ConditionSearch(
              selected: _conditions,
              onChanged: (codes) => setState(() => _conditions = codes),
            ),
          ],
        ),
      ),
    );
  }
}
