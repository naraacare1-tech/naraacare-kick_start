import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/step_saver.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// O1 (Onboarding 1 Default/Typing/Filled): sex as two avatar cards, then
/// the full name (asked here, not at sign-up, OQ-65).
class Step1IdentityScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<Step1IdentityScreen> createState() => _Step1State();
}

class _Step1State extends ConsumerState<Step1IdentityScreen>
    with StepSaver<Step1IdentityScreen> {
  @override
  int get step => 1;

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: draft.fullName);
  late String? _sex = draft.sex;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_form.currentState!.validate() || _sex == null) return;
    final name = InputValidators.normalise(_name.text);
    draft
      ..sex = _sex
      ..fullName = name;
    await saveAndContinue({
      'biological_sex': _sex,
      'avatar_code': draft.avatarCode(),
      'full_name': name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OnboardingScaffold(
      step: step,
      title: l10n.step1Title,
      why: l10n.step1Why,
      busy: busy,
      error: error,
      onBack: goBack,
      onNext: _sex == null ? null : _next,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final (code, label) in [
                  ('female', l10n.sexFemale),
                  ('male', l10n.sexMale),
                ]) ...[
                  Expanded(
                    child: _SexCard(
                      label: label,
                      sex: code,
                      selected: _sex == code,
                      onTap: () => setState(() => _sex = code),
                    ),
                  ),
                  if (code == 'female') const SizedBox(width: NcSpace.cardGap),
                ],
              ],
            ),
            const SizedBox(height: NcSpace.sectionGap),
            NcTextField(
              controller: _name,
              validator: InputValidators.name,
              maxLength: 100,
              label: l10n.fullNameLabel,
              hint: l10n.fullNameHint,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
            ),
          ],
        ),
      ),
    );
  }
}

class _SexCard extends StatelessWidget {
  const new({
    required this.label,
    required this.sex,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NcRadius.l),
        child: Container(
          padding: const EdgeInsets.all(NcSpace.cardPadding),
          decoration: BoxDecoration(
            color: selected ? nc.primarySurface : nc.inputFill,
            borderRadius: BorderRadius.circular(NcRadius.l),
            border: Border.all(
              color: selected ? nc.primary : nc.inputFill,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              NcAvatarFigure(sex: sex, look: AvatarLook.pick, height: 220),
              const SizedBox(height: NcSpace.inputGap),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
