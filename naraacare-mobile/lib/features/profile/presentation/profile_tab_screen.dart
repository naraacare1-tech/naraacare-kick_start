import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';

/// Profile tab (Figma "Profile", S14): name, @username, STAR badge, the
/// notification bell and Settings, the avatar and the three counts
/// (connections, streak, circles). Each count opens its screen.
class ProfileTabScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final me = ref.watch(meProvider).value;
    final counts = me?.counts;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [nc.surface, nc.primarySurface, nc.primary.withAlpha(90)],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(meProvider.future),
            child: LayoutBuilder(
              builder: (context, box) => ListView(
                padding: EdgeInsets.symmetric(horizontal: nc.screenPadding),
                children: [
                  const SizedBox(height: NcSpace.cardGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me?.profile.fullName ?? '',
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: NcSpace.xs),
                            Wrap(
                              spacing: NcSpace.inputGap,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (me?.username != null)
                                  Text(
                                    '@${me!.username}',
                                    style: text.bodySmall?.copyWith(
                                      color: nc.textSecondary,
                                    ),
                                  ),
                                if (me?.isStar ?? false) const NcStarBadge(),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _RoundButton(
                        icon: Icons.notifications_none,
                        tooltip: l10n.notificationsTitle,
                        onTap: () => context.push(Routes.myNotifications),
                      ),
                      const SizedBox(width: NcSpace.inputGap),
                      _RoundButton(
                        icon: Icons.settings_outlined,
                        tooltip: l10n.settingsTitle,
                        onTap: () => context.push(Routes.settings),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: (box.maxHeight - 120).clamp(360, 640),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: NcSpace.sectionGap,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Count(
                                icon: Icons.people_outline,
                                value: counts?.connections ?? 0,
                                label: l10n.profileConnections,
                                onTap: () => context.push(Routes.connections),
                              ),
                              _Count(
                                icon: Icons.local_fire_department_outlined,
                                colour: const Color(0xFFF59E0B),
                                value: counts?.currentStreak ?? 0,
                                label: l10n.activeStreak,
                                onTap: () => context.push(Routes.streak),
                              ),
                              _Count(
                                icon: Icons.diversity_3_outlined,
                                colour: nc.success,
                                value: counts?.circles ?? 0,
                                label: l10n.profileCircles,
                                onTap: () => context.go(Routes.careCircle),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: NcAvatarFigure(
                              sex: me?.profile.biologicalSex,
                              look: AvatarLook.pick, // the original choice (jacket / shirt), owner 2026-11-11
                              semanticLabel: l10n.profileAvatarLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const new({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Material(
      color: nc.surface,
      shape: CircleBorder(side: BorderSide(color: nc.inputFill)),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: nc.textPrimary),
        onPressed: onTap,
      ),
    );
  }
}

/// One count of the header: icon + two-digit number; the label is for
/// screen readers (the Figma shows icons only).
class _Count extends StatelessWidget {
  const new({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.colour,
  });

  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(NcRadius.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: NcSpace.buttonGap,
            horizontal: NcSpace.xs,
          ),
          child: Row(
            children: [
              Icon(icon, color: colour ?? nc.primary),
              const SizedBox(width: NcSpace.buttonGap),
              Text(
                value.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
