import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/core/utils/units.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/onboarding/presentation/onboarding_draft.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/measure_inputs.dart';
import 'package:naraacare/features/privacy/presentation/consent_sheet.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';

/// O6-1 / "Onboarding 7": the avatar chosen in step 1 and a summary of the
/// saved profile (Figma: no calorie or hydration targets; owner 2026-11-07).
/// Edit Details goes back to step 1; Save my avatar asks for consent and
/// completes onboarding.
class ResultScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  late Future<Profile> _data = _load();
  bool _busy = false;
  String? _error;

  Future<Profile> _load() async {
    final state = await ref.read(profileApiProvider).onboarding();
    ref.read(onboardingDraftProvider).fill(state.soFar);
    return state.soFar;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final policies = await ref.read(authApiProvider).policyVersions();
      if (!mounted) return;
      setState(() => _busy = false); // no spinner behind the sheet
      final consents = await showConsentSheet(context, policies);
      if (consents == null || !mounted) return;
      context.go(Routes.onboardingGenerating, extra: consents);
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
    final draft = ref.watch(onboardingDraftProvider);
    final reference = ref.watch(referenceDataProvider).value;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: FutureBuilder<Profile>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Padding(
                padding: EdgeInsets.all(nc.screenPadding),
                child: Center(
                  child: NcErrorBanner(
                    message: error is ApiError
                        ? featureErrorMessage(l10n, error)
                        : l10n.errorGeneric,
                    actionLabel: l10n.actionRetry,
                    onAction: () => setState(() => _data = _load()),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snapshot.data!;
            String label(
              List<({String code, String label})>? items,
              String? c,
            ) => reference?.label(items ?? const [], c) ?? (c ?? '');
            final height = profile.heightCm ?? 0;
            final ftIn = Units.cmToFeetInches(height);
            String weight(double? kg) =>
                '${WeightField.display(kg, pounds: draft.pounds)} '
                '${draft.pounds ? l10n.unitLb : l10n.unitKg}';
            final rows = [
              (l10n.resultName, profile.fullName ?? ''),
              (
                l10n.resultHeight,
                draft.feetInches
                    ? l10n.feetInches(ftIn.feet, ftIn.inches)
                    : '${height.round()} ${l10n.unitCm}',
              ),
              (l10n.resultWeight, weight(profile.weightKg)),
              (l10n.resultAge, '${profile.ageYears ?? ''}'),
              (
                l10n.resultGoal,
                label(reference?.weightGoals, profile.weightGoal),
              ),
              (l10n.resultTarget, weight(profile.targetWeightKg)),
              (
                l10n.resultActivity,
                label(reference?.activityLevels, profile.activityLevel),
              ),
              (
                l10n.resultConditions,
                profile.conditionCodes.isEmpty
                    ? l10n.conditionsNone
                    : profile.conditionCodes
                          .map((c) => label(reference?.medicalConditions, c))
                          .join(', '),
              ),
              (
                l10n.resultBodyType,
                label(reference?.bodyTypes, profile.bodyType),
              ),
            ];
            return ListView(
              padding: EdgeInsets.all(nc.screenPadding),
              children: [
                Center(
                  child: NcAvatarFigure(
                    sex: profile.biologicalSex ?? draft.sex,
                    look: AvatarLook.pick,
                    height: NcSize.icon * 10,
                  ),
                ),
                const SizedBox(height: NcSpace.cardGap),
                Text(
                  l10n.resultTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: NcSpace.sectionGap),
                for (final (name, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: NcSpace.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(color: nc.textSecondary),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            value,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: NcSpace.sectionGap),
                if (_error != null) ...[
                  NcErrorBanner(message: _error!),
                  const SizedBox(height: NcSpace.buttonGap),
                ],
                NcButton(
                  label: l10n.saveAvatar,
                  loading: _busy,
                  onPressed: _save,
                ),
                const SizedBox(height: NcSpace.inputGap),
                NcButton(
                  label: l10n.editDetails,
                  variant: NcButtonVariant.secondary,
                  onPressed: _busy
                      ? null
                      : () => context.go(Routes.onboardingStep(1)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
