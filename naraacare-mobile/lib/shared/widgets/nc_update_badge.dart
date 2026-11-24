import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Which Home avatar an update belongs to.
enum UpdateTracker { water, food, sleep }

/// One confirmation shown beside the avatar ("250 ml of water added", "Meal
/// saved", "Sleep saved"). Fixed copy only.
@immutable
class AvatarUpdate {
  const new({
    required this.id,
    required this.tracker,
    required this.title,
    this.offline = false,
  });

  final int id;
  final UpdateTracker tracker;
  final String title;

  /// Saved on the phone; it syncs when the phone is back online.
  final bool offline;
}

/// The latest update, cleared after [shownFor]. Replaces the bottom toast for
/// saves that return to Home (owner 2026-11-24: the toast covered the
/// buttons; show it in the empty space beside the avatar instead).
class AvatarUpdates extends Notifier<AvatarUpdate?> {
  static const shownFor = Duration(seconds: 4);

  Timer? _timer;
  int _next = 0;

  @override
  AvatarUpdate? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void post(UpdateTracker tracker, String title, {bool offline = false}) {
    _timer?.cancel();
    state = AvatarUpdate(
      id: _next++,
      tracker: tracker,
      title: title,
      offline: offline,
    );
    _timer = Timer(shownFor, () => state = null);
  }
}

final avatarUpdatesProvider = NotifierProvider<AvatarUpdates, AvatarUpdate?>(
  AvatarUpdates.new,
);

/// The side badge of a Home avatar: the latest update of [tracker] for a few
/// seconds; otherwise the standing [caution] (for example the
/// over-hydration safety note), if any.
class NcUpdateBadge extends ConsumerWidget {
  const new({required this.tracker, super.key, this.caution});

  final UpdateTracker tracker;
  final String? caution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final update = ref.watch(avatarUpdatesProvider);
    final Widget child;
    if (update != null && update.tracker == tracker) {
      child = _Badge(
        key: ValueKey(update.id),
        icon: switch (tracker) {
          UpdateTracker.water => Icons.water_drop,
          UpdateTracker.food => Icons.restaurant,
          UpdateTracker.sleep => Icons.bedtime,
        },
        title: update.title,
        subtitle: update.offline ? l10n.badgeSyncsLater : null,
        colour: nc.success,
        background: nc.successSurface,
        live: true,
      );
    } else if (caution case final text?) {
      child = _Badge(
        key: const ValueKey('caution'),
        icon: Icons.warning_amber_rounded,
        title: text,
        colour: nc.error,
        background: nc.errorSurface,
      );
    } else {
      child = const SizedBox.shrink(key: ValueKey('none'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: child,
    );
  }
}

class _Badge extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.colour,
    required this.background,
    super.key,
    this.subtitle,
    this.live = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color colour;
  final Color background;

  /// Announced by screen readers when it appears.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nc = context.nc;
    return Semantics(
      liveRegion: live,
      container: true,
      child: Material(
        color: background,
        elevation: 2,
        shadowColor: nc.textSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(NcRadius.l),
        child: Padding(
          padding: const EdgeInsets.all(NcSpace.buttonGap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colour, size: NcSize.icon),
              const SizedBox(height: NcSpace.xs),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(
                  color: colour,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle case final s?) ...[
                const SizedBox(height: NcSpace.xs),
                Text(
                  s,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: nc.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
