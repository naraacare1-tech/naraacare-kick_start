import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart'
    show AvatarType;
import 'package:naraacare/features/care_circle/presentation/avatar_share_sheet.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_card.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_avatar_menu.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_update_badge.dart';

String avatarStateLabel(AppLocalizations l10n, AvatarStateCode state) =>
    switch (state) {
      AvatarStateCode.empty => l10n.avatarEmpty,
      AvatarStateCode.fueling => l10n.avatarFueling,
      AvatarStateCode.energized => l10n.avatarEnergized,
      AvatarStateCode.goalMet => l10n.avatarGoalMet,
      AvatarStateCode.overfilled => l10n.avatarOverfilled,
    };

/// N1 "Home/Nutrition": the Food avatar page with today's kcal against the
/// goal (server values) and the state; the colour fill is the avatar fill
/// (doc 06 section 2.8). The Add Meal button is on Home. Tapping the
/// card opens Today's Nutrition (N2). Queued offline meals show as syncing.
class NutritionAvatarCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final summary = ref.watch(dailySummaryProvider);
    final sex = ref.watch(meProvider).value?.profile.biologicalSex;
    final pending = ref.watch(pendingMealsProvider).value ?? const [];
    final data = summary.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: data == null ? null : () => showTodaysNutrition(context),
          child: NcAvatarStage(
            sex: sex,
            look: AvatarLook.food,
            fill: data == null ? 0 : (data.fillPct / 100).clamp(0, 1),
            onShare: () => showAvatarShareSheet(context, AvatarType.nutrition),
            sideBadge: const NcUpdateBadge(tracker: UpdateTracker.food),
            actions: [
              NcAvatarAction(
                icon: Icons.more_vert,
                tooltip: l10n.moreOptions,
                onPressed: () => showAvatarMenu(context, [
                  AvatarMenuItem(
                    icon: Icons.history,
                    label: l10n.recentUpdates,
                    onTap: () => context.push(Routes.recentMeals),
                  ),
                  AvatarMenuItem(
                    icon: Icons.pie_chart_outline,
                    label: l10n.todaysNutrition,
                    onTap: () => showTodaysNutrition(context),
                  ),
                ]),
              ),
              NcAvatarAction(
                icon: Icons.info_outline,
                tooltip: l10n.nutritionInfo,
                color: nc.star,
                onPressed: () => showNutritionInfo(context),
              ),
            ],
            card: NcAvatarCard(
              label: l10n.avatarFood,
              value: data == null
                  ? (summary.hasError ? l10n.nutritionUnavailable : '…')
                  : l10n.kcalValueShort(data.calories),
              caption: data?.allowanceKcal == null
                  ? null
                  : '${l10n.ofGoalKcal(data!.allowanceKcal!)} · '
                        '${avatarStateLabel(l10n, data.state)}',
              icon: Icons.restaurant_outlined,
              progress: data == null ? 0 : (data.fillPct / 100).clamp(0, 1),
              pending: pending.isNotEmpty,
            ),
          ),
        ),
        // No text under the avatar (owner 2026-11-24): meals waiting to sync
        // show as "pending" on the card.
      ],
    );
  }
}

/// N2 "Today's Nutrition" (Figma "On press"): calories against the goal and
/// the nutrients of the user's tier; STANDARD sees the STAR upsell.
Future<void> showTodaysNutrition(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.todaysNutrition,
    builder: (context) => const _TodaysNutrition(),
  );
}

class _TodaysNutrition extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final summary = ref.watch(dailySummaryProvider).value;
    if (summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final updated = summary.lastUpdated;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.basedOnLoggedMeals,
                style: text.bodySmall?.copyWith(color: nc.textSecondary),
              ),
            ),
            Text(
              summary.view.lockedCount == 0 ? l10n.tierIncluded : l10n.tierFree,
              style: text.labelSmall?.copyWith(color: nc.primary),
            ),
          ],
        ),
        const SizedBox(height: NcSpace.inputGap),
        NutrientList(view: summary.view, caloriesGoal: summary.allowanceKcal),
        if (updated != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NcSpace.inputGap),
            child: Text(
              l10n.lastUpdatedAt(
                TimeOfDay.fromDateTime(updated.toLocal()).format(context),
              ),
              style: text.bodySmall?.copyWith(color: nc.textSecondary),
            ),
          ),
        if (summary.view.lockedCount > 0)
          UpsellCard(lockedCount: summary.view.lockedCount)
        else
          Text(
            l10n.allNutrientsUnlocked,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: nc.success),
          ),
      ],
    );
  }
}

final FutureProvider<({int kcal, int carbsG, int fatG, int proteinG})>
_targetsProvider = FutureProvider(
  (ref) => ref.watch(profileApiProvider).targetsToday(),
);

/// Home/Nutrition/Info: how the goal is set (copy from the App Design page;
/// the BMI "Decide" line is left out until product decides, see docs).
Future<void> showNutritionInfo(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.infoGoalTitle,
    builder: (context) => const _NutritionInfo(),
  );
}

class _NutritionInfo extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final targets = ref.watch(_targetsProvider).value;
    Widget section(String title, String body, [String? extra]) => Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.cardGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(height: NcSpace.xs),
          Text(body, style: text.bodySmall),
          if (extra != null) ...[
            const SizedBox(height: NcSpace.xs),
            Text(
              extra,
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section(
              l10n.infoGoalTitle,
              l10n.infoGoalBody,
              targets == null ? null : l10n.infoTodayGoal(targets.kcal),
            ),
            section(l10n.infoWorkoutsTitle, l10n.infoWorkoutsBody),
            section(
              l10n.infoNutrientsTitle,
              l10n.infoNutrientsBody,
              targets == null
                  ? null
                  : l10n.infoTargets(
                      targets.carbsG,
                      targets.fatG,
                      targets.proteinG,
                    ),
            ),
            section(l10n.infoLoggingTitle, l10n.infoLoggingBody),
            section(l10n.infoNoteTitle, l10n.infoNoteBody),
          ],
        ),
      ),
    );
  }
}
