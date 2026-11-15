import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/onboarding/presentation/onboarding_draft.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// Shared behaviour of onboarding steps: save the step, then go on; back
/// goes to the previous step (step 1 back to the onboarding start).
mixin StepSaver<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  int get step;

  bool busy = false;
  String? error;

  OnboardingDraft get draft => ref.read(onboardingDraftProvider);

  void goBack() => context.go(
    step == 1 ? Routes.onboarding : Routes.onboardingStep(step - 1),
  );

  /// Saves [fields] for this step; returns false (and shows the error) when
  /// the API refuses them.
  Future<bool> save(Map<String, Object?> fields) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(profileApiProvider).saveStep(step, fields);
      return true;
    } on ApiError catch (e) {
      if (mounted) setState(() => error = featureErrorMessage(l10n, e));
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveAndContinue(Map<String, Object?> fields) async {
    if (!await save(fields) || !mounted) return;
    context.go(
      step < 6 ? Routes.onboardingStep(step + 1) : Routes.onboardingResult,
    );
  }
}
