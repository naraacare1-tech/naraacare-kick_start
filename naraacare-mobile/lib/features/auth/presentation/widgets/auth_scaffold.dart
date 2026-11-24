import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/screen_guard.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/responsive.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Layout shared by the auth screens (Figma Login Process): logo on top,
/// heading and subtitle, then the form. Auth screens block screenshots and
/// screen recording (FLAG_SECURE / secure overlay, OQ-50, SEC-5.5).
class AuthScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    super.key,
    this.subtitle,
    this.showBack = false,
    this.secure = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;
  final bool secure;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final page = Scaffold(
      backgroundColor: nc.surface,
      appBar: showBack
          ? AppBar(backgroundColor: nc.surface, elevation: 0)
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(nc.screenPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: NcSpace.cardGap),
              Center(
                child: Image.asset(
                  'assets/brand/logo.png',
                  height: context.scaled(NcSize.buttonHeight),
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(height: NcSpace.cardGap),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: NcSpace.inputGap),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: nc.textSecondary),
                ),
              ],
              const SizedBox(height: NcSpace.sectionGap),
              ...children,
            ],
          ),
        ),
      ),
    );
    return secure ? ScreenGuard(child: page) : page;
  }
}

/// "Already have an account? Sign In" style footer.
class AuthPromptLink extends StatelessWidget {
  const new({
    required this.prompt,
    required this.action,
    required this.onTap,
    super.key,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final style = Theme.of(context).textTheme.bodySmall;
    // Wraps onto two lines on narrow screens or with large text.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: style?.copyWith(color: nc.primary)),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: style?.copyWith(
              color: nc.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline error under a form (fixed copy).
class FormErrorText extends StatelessWidget {
  const new(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.cardGap),
      child: Text(
        message!,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.nc.error),
      ),
    );
  }
}

/// "or" between the form and the social buttons.
class OrDivider extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NcSpace.cardGap),
      child: Row(
        children: [
          Expanded(child: Divider(color: nc.inputFill)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NcSpace.inputGap),
            child: Text(
              AppLocalizations.of(context).orDivider,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: nc.textSecondary),
            ),
          ),
          Expanded(child: Divider(color: nc.inputFill)),
        ],
      ),
    );
  }
}
