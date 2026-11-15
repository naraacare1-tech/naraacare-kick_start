import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/condition_search.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/goal_dropdown.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/measure_inputs.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';
import 'package:naraacare/features/profile/data/reference_data.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// ST2 Edit Profile: the onboarding fields, BMI read-only. Only changed
/// fields are sent (PATCH /me/profile); the API recalculates today's
/// targets and re-applies the BMI goal guardrails (GOAL_NOT_ALLOWED).
class EditProfileScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final me = ref.watch(meProvider);
    final reference = ref.watch(referenceDataProvider);
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.editProfile),
        backgroundColor: nc.surface,
      ),
      body: switch ((me, reference)) {
        (AsyncData(value: final me), AsyncData(value: final reference)) =>
          _EditProfileForm(me: me, reference: reference),
        (AsyncError(), _) || (_, AsyncError()) => Center(
          child: TextButton(
            onPressed: () {
              ref
                ..invalidate(meProvider)
                ..invalidate(referenceDataProvider);
            },
            child: Text(l10n.actionRetry),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const new({required this.me, required this.reference});

  final Me me;
  final ReferenceData reference;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  static final Validator _ageValidator = InputValidators.integer(
    min: 18,
    max: 100,
  );

  final _form = GlobalKey<FormState>();
  late final Profile _p = widget.me.profile;
  late final _name = TextEditingController(text: _p.fullName);
  late final _age = TextEditingController(text: _p.ageYears?.toString());
  late final bool _feet = widget.me.usesFeetInches;
  late final bool _pounds = widget.me.usesPounds;
  late final _weight = TextEditingController(
    text: WeightField.display(_p.weightKg, pounds: _pounds),
  );
  late final _target = TextEditingController(
    text: WeightField.display(_p.targetWeightKg, pounds: _pounds),
  );
  late String? _sex = _p.biologicalSex;
  late double _heightCm = _p.heightCm ?? 160;
  late String? _goal = _p.weightGoal;
  late List<String> _conditions = [..._p.conditionCodes];
  late String? _activity = _p.activityLevel;
  late String? _bodyType = _p.bodyType;
  List<String>? _allowedGoals;
  double? _bmi;
  Timer? _debounce;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGoals());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _age, _weight, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadGoals() async {
    final kg = WeightField.kgFrom(_weight.text, pounds: _pounds);
    try {
      final options = await ref
          .read(profileApiProvider)
          .goalOptions(weightKg: kg, heightCm: _heightCm);
      if (mounted) {
        setState(() {
          _allowedGoals = options.allowedGoals;
          _bmi = options.bmi;
        });
      }
    } on ApiError {
      // Keep the last options; saving re-checks the goal.
    }
  }

  void _measureChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadGoals);
  }

  Map<String, Object?> _changes() {
    final name = InputValidators.normalise(_name.text);
    final age = int.parse(InputValidators.normalise(_age.text));
    final weight = WeightField.kgFrom(_weight.text, pounds: _pounds)!;
    final target = WeightField.kgFrom(_target.text, pounds: _pounds)!;
    bool differs(double? a, double b) => a == null || (a - b).abs() >= 0.005;
    final avatarChanged = _sex != _p.biologicalSex || _bodyType != _p.bodyType;
    return {
      if (name != _p.fullName) 'full_name': name,
      if (_sex != _p.biologicalSex) 'biological_sex': _sex,
      if (avatarChanged) 'avatar_code': '${_sex}_$_bodyType',
      if (age != _p.ageYears) 'age_years': age,
      if (differs(_p.heightCm, _heightCm))
        'height_cm': wireDecimal(_heightCm, 1),
      if (differs(_p.weightKg, weight)) 'weight_kg': wireDecimal(weight, 2),
      if (differs(_p.targetWeightKg, target))
        'target_weight_kg': wireDecimal(target, 2),
      if (_goal != _p.weightGoal) 'weight_goal': _goal,
      if (_conditions.join(',') != _p.conditionCodes.join(','))
        'medical_condition_codes': _conditions,
      if (_activity != _p.activityLevel) 'activity_level': _activity,
      if (_bodyType != _p.bodyType) 'body_type': _bodyType,
    };
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _goal == null) return;
    final changes = _changes();
    if (changes.isEmpty) {
      context.pop();
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileApiProvider).patchProfile(changes);
      ref.invalidate(meProvider);
      if (!mounted) return;
      showNcToast(context, l10n.profileSaved);
      context.pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final reference = widget.reference;
    const gap = SizedBox(height: NcSpace.cardGap);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    Widget dropdown(
      String title,
      List<RefItem> items,
      String? value,
      ValueChanged<String?> onChanged,
    ) => DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.code == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item.code, child: Text(item.label)),
      ],
      onChanged: onChanged,
    );
    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          NcTextField(
            controller: _name,
            validator: InputValidators.name,
            maxLength: 100,
            label: l10n.fullNameLabel,
            autofillHints: const [AutofillHints.name],
          ),
          gap,
          dropdown(
            l10n.sexLabel,
            [
              (code: 'female', label: l10n.sexFemale),
              (code: 'male', label: l10n.sexMale),
            ],
            _sex,
            (v) => setState(() => _sex = v),
          ),
          gap,
          NcTextField(
            controller: _age,
            validator: _ageValidator,
            maxLength: 3,
            label: l10n.ageLabel,
            keyboardType: TextInputType.number,
            inputFormatters: [NcTextField.digitsOnly],
          ),
          gap,
          label(l10n.heightLabel),
          HeightPicker(
            heightCm: _heightCm,
            feetInches: _feet,
            height: NcSize.icon * 5,
            onChanged: (cm) {
              setState(() => _heightCm = cm);
              _measureChanged();
            },
          ),
          gap,
          label(l10n.weightLabel),
          WeightField(
            controller: _weight,
            pounds: _pounds,
            hint: l10n.weightHint,
            onChanged: (_) => _measureChanged(),
          ),
          gap,
          label(l10n.targetWeightLabel),
          WeightField(
            controller: _target,
            pounds: _pounds,
            hint: l10n.targetHint,
          ),
          gap,
          GoalDropdown(
            allowed: _allowedGoals,
            value: _goal,
            onChanged: (goal) => setState(() => _goal = goal),
          ),
          if (_bmi != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.bmiLabel),
              trailing: Text(_bmi!.toStringAsFixed(1)),
            ),
          gap,
          dropdown(
            l10n.activityLabel,
            reference.activityLevels,
            _activity,
            (v) => setState(() => _activity = v),
          ),
          gap,
          dropdown(
            l10n.bodyTypeLabel,
            reference.bodyTypes,
            _bodyType,
            (v) => setState(() => _bodyType = v),
          ),
          gap,
          ConditionSearch(
            selected: _conditions,
            onChanged: (codes) => setState(() => _conditions = codes),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
              child: Text(_error!, style: TextStyle(color: nc.error)),
            ),
          NcButton(label: l10n.saveButton, loading: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
