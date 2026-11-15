import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/wave_progress.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// Layout of onboarding steps 1-6 (Figma Onboarding 1..6): wave progress
/// with "n/6", title, "Why it matters?" note, the step's content, then
/// Next and Go Back.
class OnboardingScaffold extends StatelessWidget {
  const new({
    required this.step,
    required this.title,
    required this.why,
    required this.child,
    required this.onNext,
    required this.onBack,
    super.key,
    this.busy = false,
    this.error,
  });

  static const totalSteps = 6;

  final int step;
  final String title;
  final String why;
  final Widget child;

  /// Null disables Next (step not filled in yet).
  final VoidCallback? onNext;
  final VoidCallback onBack;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(nc.screenPadding),
              child: Row(
                children: [
                  Expanded(child: WaveProgress(value: step / totalSteps)),
                  const SizedBox(width: NcSpace.buttonGap),
                  Text(
                    l10n.stepOf(step, totalSteps),
                    style: text.bodySmall?.copyWith(color: nc.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: nc.screenPadding),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: NcSpace.sectionGap),
                    child,
                    const SizedBox(height: NcSpace.sectionGap),
                    _WhyItMatters(text: why),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(nc.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: nc.error),
                      ),
                    ),
                  NcButton(
                    label: l10n.nextButton,
                    loading: busy,
                    onPressed: onNext,
                  ),
                  const SizedBox(height: NcSpace.inputGap),
                  NcButton(
                    label: l10n.goBack,
                    variant: NcButtonVariant.ghost,
                    onPressed: busy ? null : onBack,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhyItMatters extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final style = Theme.of(context).textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.all(NcSpace.cardPadding),
      decoration: BoxDecoration(
        color: nc.primarySurface,
        borderRadius: BorderRadius.circular(NcRadius.m),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: NcSize.iconSmall, color: nc.primary),
          const SizedBox(width: NcSpace.inputGap),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style?.copyWith(color: nc.textBody),
                children: [
                  TextSpan(
                    text: '${AppLocalizations.of(context).whyItMatters} ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
