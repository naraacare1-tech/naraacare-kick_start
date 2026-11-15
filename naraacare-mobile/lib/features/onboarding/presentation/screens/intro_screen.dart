import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// A1a intro slides, first install only (OQ-62), as in Figma "Onboarding 1 -
/// Meet your health avatars", "Onboarding 2 - Goals made for your body" and
/// "Onboarding 3 - Care for each other": an illustration, the step counter
/// and Skip, the dots, the text and Next; the last page's "Get Started" (or
/// Skip) calls [onDone], which records `intro_seen` and opens Sign Up.
/// Shown on first install and from Welcome's Get Started.
/// The numbers on the cards are examples, not the user's data.
class IntroScreen extends StatefulWidget {
  const new({required this.onDone, super.key});

  final Future<void> Function() onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final slides = [
      (l10n.intro1Title, l10n.intro1Body, const _AvatarsArt()),
      (l10n.intro2Title, l10n.intro2Body, const _GoalsArt()),
      (l10n.intro3Title, l10n.intro3Body, const _CircleArt()),
    ];
    final last = _index == slides.length - 1;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: nc.screenPadding + 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: NcSize.buttonHeight,
                child: Row(
                  children: [
                    Text(
                      l10n.introStep(_index + 1, slides.length),
                      style: text.labelMedium?.copyWith(
                        color: nc.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (!last)
                      TextButton(
                        onPressed: widget.onDone,
                        child: Text(l10n.introSkip),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => slides[i].$3,
                ),
              ),
              const SizedBox(height: NcSpace.cardGap),
              Row(
                // Centred under the illustration (owner 2026-11-11).
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                        horizontal: NcSpace.inputGap / 2,
                      ),
                      width: i == _index
                          ? NcSpace.sectionGap
                          : NcSpace.inputGap,
                      height: NcSpace.xs + 2,
                      decoration: BoxDecoration(
                        color: i == _index ? nc.primary : nc.primaryDisabled,
                        borderRadius: BorderRadius.circular(NcRadius.full),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: NcSpace.cardGap),
              Text(slides[_index].$1, style: text.headlineSmall),
              const SizedBox(height: NcSpace.inputGap),
              Text(
                slides[_index].$2,
                style: text.bodyMedium?.copyWith(color: nc.textSecondary),
              ),
              const SizedBox(height: NcSpace.cardGap),
              NcButton(
                label: last ? l10n.introGetStarted : l10n.introNext,
                onPressed: last
                    ? widget.onDone
                    : () => _pages.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
              ),
              const SizedBox(height: NcSpace.cardGap),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small white card with an icon, a label and a value (the Figma badges).
class _Badge extends StatelessWidget {
  const new({
    required this.icon,
    required this.colour,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final Color colour;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Material(
      color: nc.surface,
      elevation: 3,
      shadowColor: nc.scrim.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(NcRadius.m),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NcSpace.buttonGap,
          vertical: NcSpace.inputGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: NcSize.iconSmall - 2, color: colour),
                const SizedBox(width: NcSpace.xs),
                Text(
                  label,
                  style: text.labelSmall?.copyWith(color: nc.textSecondary),
                ),
              ],
            ),
            Text(
              value,
              style: text.titleMedium?.copyWith(
                color: colour,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (caption != null)
              Text(
                caption!,
                style: text.labelSmall?.copyWith(
                  color: nc.textSecondary,
                  fontSize: NcTypeScale.footnote - 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Meet your health avatars": the three avatars (food, water, sleep) with a
/// water, a meal and a sleep badge.
class _AvatarsArt extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        return Stack(
          children: [
            Positioned(
              left: box.maxWidth * 0.02,
              bottom: h * 0.08,
              height: h * 0.62,
              child: const NcAvatarFigure(
                sex: 'male',
                look: AvatarLook.food,
                fill: 0.45,
              ),
            ),
            Positioned(
              right: box.maxWidth * 0.02,
              bottom: h * 0.08,
              height: h * 0.62,
              child: const NcAvatarFigure(
                sex: 'male',
                look: AvatarLook.neutral,
                fill: 0.6,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: h * 0.02,
              height: h * 0.8,
              child: const Center(
                child: NcAvatarFigure(
                  sex: 'male',
                  look: AvatarLook.water,
                  fill: 0.7,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: h * 0.02,
              child: _Badge(
                icon: Icons.water_drop_outlined,
                colour: NcColors.avatarWater,
                label: l10n.introWater,
                value: l10n.introWaterValue,
                caption: l10n.introWaterCaption,
              ),
            ),
            Positioned(
              right: 0,
              top: h * 0.36,
              child: _Badge(
                icon: Icons.restaurant_outlined,
                colour: NcColors.avatarNutrition,
                label: l10n.introMeal,
                value: l10n.introMealValue,
                caption: l10n.introMealCaption,
              ),
            ),
            Positioned(
              left: 0,
              bottom: h * 0.04,
              child: _Badge(
                icon: Icons.bedtime_outlined,
                colour: NcColors.avatarSleep,
                label: l10n.introSleep,
                value: l10n.introSleepValue,
                caption: l10n.introSleepCaption,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "Goals made for your body": a figure, the profile tags it comes from and
/// the two goals worked out from them.
class _GoalsArt extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final tags = [
      l10n.introTagFemale,
      l10n.introTagAge,
      l10n.introTagHeight,
      l10n.introTagBody,
      l10n.introTagActivity,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: NcSpace.cardGap),
            child: NcAvatarFigure(sex: 'female', look: AvatarLook.neutral),
          ),
        ),
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.introFromProfile,
                style: text.labelSmall?.copyWith(
                  color: nc.textSecondary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: NcSpace.inputGap),
              Wrap(
                spacing: NcSpace.xs,
                runSpacing: NcSpace.xs,
                children: [
                  for (final tag in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NcSpace.inputGap + 2,
                        vertical: NcSpace.xs,
                      ),
                      decoration: BoxDecoration(
                        color: nc.primarySurface,
                        borderRadius: BorderRadius.circular(NcRadius.full),
                      ),
                      child: Text(
                        tag,
                        style: text.labelSmall?.copyWith(color: nc.textBody),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: NcSpace.inputGap),
                child: Center(
                  child: Icon(
                    Icons.south,
                    size: NcSize.icon,
                    color: nc.primary,
                  ),
                ),
              ),
              _Badge(
                icon: Icons.water_drop_outlined,
                colour: NcColors.avatarWater,
                label: l10n.introDailyWater,
                value: l10n.introDailyWaterValue,
              ),
              const SizedBox(height: NcSpace.inputGap),
              _Badge(
                icon: Icons.local_fire_department_outlined,
                colour: NcColors.avatarNutrition,
                label: l10n.introDailyCalories,
                value: l10n.introDailyCaloriesValue,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Figma "Onboarding 3 - Care for each other" (1620:4548): the world map of
/// connected people ("image 78", assets/illustrations/world_care.png) with
/// three cards laid out as in the 384 x 510 design box: a circle update top
/// left, the streak on the right and a Rin AI tip at the bottom. The box is
/// scaled to the space the page has.
class _CircleArt extends StatelessWidget {
  const new();

  static const _w = 384.0;
  static const _h = 510.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    BoxDecoration card() => BoxDecoration(
      color: nc.surface,
      borderRadius: BorderRadius.circular(NcRadius.l),
      border: Border.all(color: nc.border.withValues(alpha: 0.5)),
      boxShadow: [
        BoxShadow(
          color: nc.scrim.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
    const title = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final sub = TextStyle(fontSize: 12, color: nc.textSecondary);
    return FittedBox(
      child: SizedBox(
        width: _w,
        height: _h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -39,
              top: 94,
              width: 420,
              height: 280,
              child: Image.asset(
                'assets/illustrations/world_care.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            Positioned(
              left: 29,
              top: 47,
              width: 208,
              child: Container(
                padding: const EdgeInsets.all(NcSpace.buttonGap),
                decoration: card(),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: nc.inputFill,
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: nc.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: NcSpace.buttonGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.introCircleNoticeValue,
                            style: title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(l10n.introCircleNotice, style: sub),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 261,
              top: 247,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NcSpace.buttonGap,
                  vertical: NcSpace.inputGap,
                ),
                decoration: card(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_outlined,
                      color: Color(0xFFF59E0B),
                      size: 18,
                    ),
                    const SizedBox(width: NcSpace.inputGap),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.introStreakValue, style: title),
                        Text(l10n.introStreak, style: sub),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 21,
              top: 377,
              width: 340,
              child: Container(
                padding: const EdgeInsets.all(NcSpace.buttonGap),
                decoration: card(),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: nc.star.withValues(alpha: 0.08),
                      child: Icon(Icons.auto_awesome, color: nc.star, size: 18),
                    ),
                    const SizedBox(width: NcSpace.buttonGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.introRin, style: title),
                          Text(l10n.introRinBody, style: sub),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
