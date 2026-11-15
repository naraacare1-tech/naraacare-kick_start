import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/errors/error_messages.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/onboarding_draft.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';
import 'package:naraacare/shared/widgets/nc_status_screen.dart';

/// A5 Email Verified, shown once after sign-up verification.
class EmailVerifiedScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NcStatusScreen(
      title: l10n.emailVerifiedTitle,
      body: l10n.emailVerifiedBody,
      actionLabel: l10n.actionContinue,
      onAction: () => context.go(Routes.onboarding),
    );
  }
}

/// O0 "After sign in/Onboarding": intro + Build my avatar. Resumes at the
/// step after the last one saved (GET /me/onboarding); a finished profile
/// goes straight to the result page.
class OnboardingStartScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingStartScreen> createState() =>
      _OnboardingStartScreenState();
}

class _OnboardingStartScreenState extends ConsumerState<OnboardingStartScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await ref.read(profileApiProvider).onboarding();
      if (!mounted) return;
      if (state.completed) {
        await ref.read(authControllerProvider).onboardingCompleted();
        return;
      }
      ref.read(onboardingDraftProvider).fill(state.soFar);
      context.go(
        state.step >= 6
            ? Routes.onboardingResult
            : Routes.onboardingStep(state.step + 1),
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = ErrorMessages.api(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NcAvatarFigure(
                    sex: 'male',
                    look: AvatarLook.neutral,
                    height: 260,
                  ),
                  SizedBox(width: NcSpace.cardGap),
                  NcAvatarFigure(
                    sex: 'female',
                    look: AvatarLook.neutral,
                    height: 248,
                  ),
                ],
              ),
              const SizedBox(height: NcSpace.sectionGap),
              Text(
                l10n.onboardingIntroTitle,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: NcSpace.cardGap),
              Text(
                l10n.onboardingIntroBody,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: nc.textSecondary),
              ),
              const Spacer(),
              if (_error != null) ...[
                NcErrorBanner(
                  message: _error!,
                  actionLabel: l10n.actionRetry,
                  onAction: _start,
                ),
                const SizedBox(height: NcSpace.buttonGap),
              ],
              NcButton(
                label: l10n.onboardingIntroButton,
                loading: _busy,
                onPressed: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
