import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart'
    show AvatarType;
import 'package:naraacare/features/care_circle/presentation/avatar_share_sheet.dart';
import 'package:naraacare/features/hydration/data/hydration_models.dart';
import 'package:naraacare/features/hydration/hydration_providers.dart';
import 'package:naraacare/features/hydration/presentation/hydration_sheets.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_card.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_avatar_menu.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:naraacare/shared/widgets/nc_update_badge.dart';

/// "2.1 L" with one decimal (doc 06 section 3: litres shown with 1 decimal).
String litres(int ml) => (ml / 1000).toStringAsFixed(1);

String hydrationHeadline(
  AppLocalizations l10n,
  HydrationStatus s,
) => switch (s.state) {
  HydrationState.empty when s.pendingMl == 0 => l10n.hydrationEmpty,
  HydrationState.goalCompleted => l10n.hydrationGoalCompleted,
  HydrationState.aboveGoal => l10n.hydrationAboveGoal(litres(s.shownIntakeMl)),
  _ => l10n.hydrationProgress(litres(s.shownIntakeMl), litres(s.dailyGoalMl)),
};

/// Share of today's goal drunk so far (0..1), counting drinks still being
/// sent: the avatar fill and ring start empty each day (owner, OQ-17).
double goalFill(HydrationStatus s) => s.dailyGoalMl <= 0
    ? 0
    : (s.shownIntakeMl / s.dailyGoalMl).clamp(0, 1).toDouble();

String bandLabel(AppLocalizations l10n, HydrationBand band) => switch (band) {
  HydrationBand.well => l10n.bandWell,
  HydrationBand.drinkSoon => l10n.bandDrinkSoon,
  HydrationBand.low => l10n.bandLow,
  HydrationBand.critical => l10n.bandCritical,
};

/// H1 "Home/Water": the Water avatar page. The headline is today's effective
/// intake against the goal; the ring and the avatar's colour fill are the
/// share of the goal drunk so far (owner 2026-11-08, OQ-17; the body-water
/// tank level stays in the info sheet). The Add Water/Drink button is on Home. Swipe up on
/// the card adds 100 mL of water, swipe down removes 100 mL (OQ-20), with
/// haptic feedback; offline the drink is queued and shown at once.
class HydrationAvatarCard extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HydrationAvatarCard> createState() =>
      _HydrationAvatarCardState();
}

class _HydrationAvatarCardState extends ConsumerState<HydrationAvatarCard> {
  static const _swipeVelocity = 300.0;

  /// A press-and-drag this far counts as a swipe even when it is slow.
  static const _swipeDistance = 48.0;
  bool _busy = false;
  double _dragDy = 0;

  Future<void> _swipe(bool up) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final catalogue = await ref.read(drinkCatalogueProvider.future);
    final water = catalogue.drinks.firstWhere((d) => d.isWater);
    setState(() => _busy = true);
    unawaited(HapticFeedback.lightImpact());
    try {
      final result = await ref
          .read(hydrationRepositoryProvider)
          .logIntake(
            drink: water,
            volumeMl: up ? catalogue.quickAddMl : -catalogue.quickAddMl,
            source: 'swipe',
          );
      if (!mounted) return;
      if (!result.queued) ref.invalidate(hydrationStatusProvider);
      ref.invalidate(todaysIntakesProvider);
      ref
          .read(avatarUpdatesProvider.notifier)
          .post(
            UpdateTracker.water,
            up
                ? l10n.swipeAdded(catalogue.quickAddMl)
                : l10n.swipeRemoved(catalogue.quickAddMl),
            offline: result.queued,
          );
    } on ApiError catch (e) {
      if (!mounted) return;
      showNcToast(
        context,
        e.code == 'WATER_BELOW_ZERO'
            ? l10n.waterBelowZero
            : featureErrorMessage(l10n, e),
        kind: NcToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final status = ref.watch(shownHydrationProvider);
    final sex = ref.watch(meProvider).value?.profile.biologicalSex;
    final data = status.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          hint: l10n.swipeHint,
          child: GestureDetector(
            onTap: data == null ? null : () => showHydrationDetails(context),
            onVerticalDragStart: data == null ? null : (_) => _dragDy = 0,
            onVerticalDragUpdate: data == null
                ? null
                : (details) => _dragDy += details.delta.dy,
            onVerticalDragEnd: data == null
                ? null
                : (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v.abs() >= _swipeVelocity) {
                      unawaited(_swipe(v < 0));
                    } else if (_dragDy.abs() >= _swipeDistance) {
                      unawaited(_swipe(_dragDy < 0));
                    }
                  },
            child: NcAvatarStage(
              sex: sex,
              look: AvatarLook.water,
              fill: data == null ? 0 : goalFill(data),
              onShare: () =>
                  showAvatarShareSheet(context, AvatarType.hydration),
              sideBadge: NcUpdateBadge(
                tracker: UpdateTracker.water,
                caution: (data?.overhydrationCaution ?? false)
                    ? l10n.overhydrationCaution
                    : null,
              ),
              actions: [
                NcAvatarAction(
                  icon: Icons.more_vert,
                  tooltip: l10n.moreOptions,
                  onPressed: () => showAvatarMenu(context, [
                    AvatarMenuItem(
                      icon: Icons.thermostat_outlined,
                      label: l10n.temperatureActivity,
                      onTap: () => showTemperatureActivitySheet(context),
                    ),
                    AvatarMenuItem(
                      icon: Icons.history,
                      label: l10n.recentUpdates,
                      onTap: () => context.push(Routes.recentIntakes),
                    ),
                  ]),
                ),
                NcAvatarAction(
                  icon: Icons.info_outline,
                  tooltip: l10n.hydrationInfo,
                  color: nc.star,
                  onPressed: () => showHydrationInfo(context),
                ),
              ],
              card: NcAvatarCard(
                label: l10n.avatarWater,
                value: data == null
                    ? (status.hasError ? l10n.hydrationUnavailable : '…')
                    : hydrationHeadline(l10n, data),
                caption: data == null
                    ? null
                    : l10n.goalPct((goalFill(data) * 100).round()),
                icon: Icons.water_drop_outlined,
                progress: data == null ? 0 : goalFill(data),
                pending: (data?.pendingMl ?? 0) > 0,
              ),
            ),
          ),
        ),
        // No text under the avatar (owner 2026-11-24): "left to drink" is in
        // the details sheet (tap the avatar); the over-hydration safety note
        // stays visible as the side badge.
      ],
    );
  }
}
