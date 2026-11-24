import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/responsive.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// A2 Welcome, Figma "Welcome" (126:18): the logo, the world map of connected
/// people (edge to edge), the serif tagline "Glow when you're well. Know when
/// they're not", Get Started (the intro slides, then Sign Up) and the Sign In
/// link.
class WelcomeScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: NcSpace.sectionGap),
                    Image.asset(
                      'assets/brand/logo.png',
                      height: context.scaled(64),
                      excludeFromSemantics: true,
                    ),
                    const Spacer(),
                    Image.asset(
                      'assets/illustrations/world_care.png',
                      fit: BoxFit.fitWidth,
                      excludeFromSemantics: true,
                    ),
                    const Spacer(),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: nc.screenPadding + NcSpace.inputGap,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.welcomeTagline,
                            textAlign: TextAlign.center,
                            // Figma uses a serif display face here; the
                            // platform serif keeps the look without
                            // bundling another font.
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontFamily: 'serif',
                                  color: nc.textBody,
                                  height: 1.3,
                                ),
                          ),
                          const SizedBox(height: NcSpace.sectionGap * 2),
                          NcButton(
                            label: l10n.welcomeGetStarted,
                            // The three intro slides first, then Sign Up.
                            onPressed: () => context.push(Routes.intro),
                          ),
                          AuthPromptLink(
                            prompt: l10n.haveAccountPrompt,
                            action: l10n.signInLink,
                            onTap: () => context.push(Routes.signIn),
                          ),
                          const SizedBox(height: NcSpace.cardGap),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
