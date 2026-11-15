import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/step_saver.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/goal_dropdown.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/measure_inputs.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// O3 (Onboarding 3): current weight (kg | lb) and the goal. The goals on
/// offer come from the API's BMI guardrails (GET /me/goal-options); the API
/// refuses a blocked goal again on save (GOAL_NOT_ALLOWED).
class Step3WeightGoalScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<Step3WeightGoalScreen> createState() => _Step3State();
}

class _Step3State extends ConsumerState<Step3WeightGoalScreen>
    with StepSaver<Step3WeightGoalScreen> {
  @override
  int get step => 3;

  final _form = GlobalKey<FormState>();
  late bool _pounds = draft.pounds;
  late final _weight = TextEditingController(
    text: WeightField.display(draft.weightKg, pounds: draft.pounds),
  );
  late String? _goal = draft.goal;
  List<String>? _allowed;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGoals());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _weight.dispose();
    super.dispose();
  }

  double? get _kg => WeightField.kgFrom(_weight.text, pounds: _pounds);

  void _weightChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadGoals);
  }

  Future<void> _loadGoals() async {
    final kg = _kg;
    if (kg == null) {
      setState(() => _allowed = null);
      return;
    }
    try {
      final options = await ref
          .read(profileApiProvider)
          .goalOptions(weightKg: kg, heightCm: draft.heightCm);
      if (!mounted) return;
      setState(() {
        _allowed = options.allowedGoals;
        if (!options.allowedGoals.contains(_goal)) _goal = null;
      });
    } on ApiError {
      if (mounted) setState(() => _allowed = null);
    }
  }

  Future<void> _next() async {
    final kg = _kg;
    if (!_form.currentState!.validate() || kg == null || _goal == null) {
      return;
    }
    draft
      ..weightKg = kg
      ..pounds = _pounds
      ..goal = _goal;
    await saveAndContinue({
      'weight_kg': wireDecimal(kg, 2),
      'weight_goal': _goal,
    });
  }

  void _toggleUnit(bool pounds) {
    final kg = _kg;
    setState(() {
      _pounds = pounds;
      _weight.text = WeightField.display(kg, pounds: pounds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OnboardingScaffold(
      step: step,
      title: l10n.step3Title,
      why: l10n.step3Why,
      busy: busy,
      error: error,
      onBack: goBack,
      onNext: _goal == null ? null : _next,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UnitToggle(
              metricLabel: l10n.unitKg,
              imperialLabel: l10n.unitLb,
              imperial: _pounds,
              onChanged: _toggleUnit,
            ),
            const SizedBox(height: NcSpace.cardGap),
            WeightField(
              controller: _weight,
              pounds: _pounds,
              hint: l10n.weightHint,
              onChanged: _weightChanged,
            ),
            const SizedBox(height: NcSpace.sectionGap),
            GoalDropdown(
              allowed: _allowed,
              value: _goal,
              onChanged: (goal) => setState(() => _goal = goal),
            ),
          ],
        ),
      ),
    );
  }
}
