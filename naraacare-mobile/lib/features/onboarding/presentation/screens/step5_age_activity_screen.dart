import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/step_saver.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/choice_card.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// O5 (Onboarding 5): age 18-100 (digits only) and one of the 4 activity
/// levels (labels from the reference data).
class Step5AgeActivityScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<Step5AgeActivityScreen> createState() => _Step5State();
}

class _Step5State extends ConsumerState<Step5AgeActivityScreen>
    with StepSaver<Step5AgeActivityScreen> {
  @override
  int get step => 5;

  static final Validator _ageValidator = InputValidators.integer(
    min: 18,
    max: 100,
  );

  final _form = GlobalKey<FormState>();
  late final _age = TextEditingController(text: draft.age?.toString());
  late String? _activity = draft.activity;

  @override
  void dispose() {
    _age.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_form.currentState!.validate() || _activity == null) return;
    final age = int.parse(InputValidators.normalise(_age.text));
    draft
      ..age = age
      ..activity = _activity;
    await saveAndContinue({'age_years': age, 'activity_level': _activity});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final levels = ref.watch(referenceDataProvider).value?.activityLevels;
    return OnboardingScaffold(
      step: step,
      title: l10n.step5Title,
      why: l10n.step5Why,
      busy: busy,
      error: error,
      onBack: goBack,
      onNext: _activity == null ? null : _next,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NcTextField(
              controller: _age,
              validator: _ageValidator,
              maxLength: 3,
              hint: l10n.ageHint,
              keyboardType: TextInputType.number,
              inputFormatters: [NcTextField.digitsOnly],
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NcSpace.sectionGap),
            Text(
              l10n.activityLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: NcSpace.inputGap),
            if (levels == null)
              const Center(child: CircularProgressIndicator())
            else
              for (final level in levels)
                Padding(
                  padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
                  child: ChoiceCard(
                    label: level.label,
                    selected: _activity == level.code,
                    onTap: () => setState(() => _activity = level.code),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
