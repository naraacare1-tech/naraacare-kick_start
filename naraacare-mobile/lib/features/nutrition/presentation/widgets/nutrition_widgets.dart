import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/shared/widgets/nc_chip.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_upsell_sheet.dart';

/// Figma's nutrient line icons (Today's Nutrition, Premium plan features).
const nutrientEmoji = <String, String>{
  'calories': '🔥',
  'protein': '🫘',
  'carbohydrates': '🍞',
  'fat': '🥑',
  'dietary_fiber': '🌾',
  'total_sugar': '🍬',
  'iron': '🩸',
  'calcium': '🦴',
  'saturated_fat': '🧈',
  'polyunsaturated_fat': '🐟',
  'monounsaturated_fat': '🫒',
  'trans_fat': '🍟',
  'cholesterol': '🫀',
  'potassium': '🍌',
  'vitamin_a': '🥕',
  'vitamin_c': '🍊',
  'sodium': '🧂',
};

String formatAmount(num? value, String unit, AppLocalizations l10n) {
  if (value == null) return l10n.nutrientUnknown;
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$text $unit';
}

/// "1.5", "2", "0.25" for quantities.
String formatQuantity(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : '$q';

/// Nutrient lines as the server returned them (already tier-filtered and
/// rounded). [caloriesGoal] turns the calories line into "eaten / goal".
class NutrientList extends StatelessWidget {
  const new({required this.view, super.key, this.caloriesGoal});

  final NutrientView view;
  final int? caloriesGoal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final n in view.nutrients)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NcSpace.xs),
            child: Row(
              children: [
                Text(nutrientEmoji[n.code] ?? '•', style: text.bodyMedium),
                const SizedBox(width: NcSpace.inputGap),
                Expanded(
                  child: Text(
                    n.code == 'calories' && caloriesGoal != null
                        ? l10n.caloriesOfGoal(
                            (n.value ?? 0).toInt(),
                            caloriesGoal!,
                          )
                        : n.label,
                    style: text.bodyMedium,
                  ),
                ),
                Text(
                  formatAmount(n.value, n.unit, l10n),
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: n.value == null ? nc.textSecondary : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Unlock STAR · 11 more nutrients" (STANDARD only).
class UpsellCard extends StatelessWidget {
  const new({required this.lockedCount, super.key});

  final int lockedCount;

  @override
  Widget build(BuildContext context) {
    if (lockedCount == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return InkWell(
      borderRadius: BorderRadius.circular(NcRadius.m),
      onTap: () => showStarUpsell(context),
      child: Container(
        padding: const EdgeInsets.all(NcSpace.cardPadding),
        decoration: BoxDecoration(
          color: nc.star.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(NcRadius.m),
          border: Border.all(color: nc.star.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const NcStarBadge(),
            const SizedBox(width: NcSpace.buttonGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.upsellTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    l10n.lockedNutrients(lockedCount),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: nc.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.lock_outline, color: nc.star),
          ],
        ),
      ),
    );
  }
}

/// The STAR upsell (every UPGRADE_REQUIRED and locked control): Upgrade
/// closes the sheet and opens My Subscriptions with the plans (S11).
Future<void> showStarUpsell(BuildContext context) => showNcUpsellSheet(
  context,
  onUpgrade: () {
    Navigator.of(context).pop();
    unawaited(GoRouter.of(context).push(Routes.subscriptions));
  },
);

/// − 1.5 + in steps of 0.25 between 0.25 and 20 (buttons only: no typing).
class QuantityStepper extends StatelessWidget {
  const new({required this.value, required this.onChanged, super.key});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final canDown = value > MealItemDraft.minQuantity;
    final canUp = value < MealItemDraft.maxQuantity;
    return Container(
      decoration: BoxDecoration(
        color: nc.inputFill,
        borderRadius: BorderRadius.circular(NcRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.decreaseQuantity,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove),
            onPressed: canDown
                ? () => onChanged(value - MealItemDraft.step)
                : null,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: NcSize.icon * 1.5),
            child: Text(
              formatQuantity(value),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: l10n.increaseQuantity,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: canUp
                ? () => onChanged(value + MealItemDraft.step)
                : null,
          ),
        ],
      ),
    );
  }
}

/// Food details (portions) per food id, shared by the Add Meal rows.
final FutureProviderFamily<FoodDetail, String> foodDetailProvider =
    FutureProvider.family<FoodDetail, String>(
      (ref, foodId) => ref.watch(nutritionApiProvider).food(foodId),
    );

/// Units the food offers (katori / piece / cup...), from the server.
class UnitDropdown extends ConsumerWidget {
  const new({
    required this.foodId,
    required this.unitCode,
    required this.unitSize,
    required this.onChanged,
    super.key,
  });

  final String foodId;
  final String unitCode;
  final String? unitSize;
  final ValueChanged<Portion> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(foodDetailProvider(foodId)).value;
    final portions = detail?.portions ?? const <Portion>[];
    Portion? selected;
    for (final p in portions) {
      if (p.unitCode == unitCode && (unitSize == null || p.size == unitSize)) {
        selected = p;
        break;
      }
    }
    if (portions.isEmpty || selected == null) {
      return const SizedBox(width: NcSize.icon, height: NcSize.icon);
    }
    return DropdownButton<Portion>(
      value: selected,
      isDense: true,
      underline: const SizedBox.shrink(),
      hint: Text(l10n.unitLabel),
      items: [
        for (final p in portions)
          DropdownMenuItem(value: p, child: Text(p.display)),
      ],
      onChanged: (p) {
        if (p != null) onChanged(p);
      },
    );
  }
}

/// Meal type suggested from the local time (doc 06 2.11): 05-11 breakfast,
/// 11-16 lunch, 16-19 snack, 19-05 dinner. The user can change it.
String suggestMealType(DateTime local) {
  final h = local.hour;
  if (h >= 5 && h < 11) return 'breakfast';
  if (h >= 11 && h < 16) return 'lunch';
  if (h >= 16 && h < 19) return 'snack';
  return 'dinner';
}

String mealTypeLabel(AppLocalizations l10n, String code) => switch (code) {
  'breakfast' => l10n.mealTypeBreakfast,
  'lunch' => l10n.mealTypeLunch,
  'snack' => l10n.mealTypeSnack,
  _ => l10n.mealTypeDinner,
};

class MealTypeChips extends StatelessWidget {
  const new({required this.selected, required this.onChanged, super.key});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: NcSpace.inputGap,
      runSpacing: NcSpace.inputGap,
      children: [
        for (final type in const ['breakfast', 'lunch', 'snack', 'dinner'])
          NcChip(
            label: mealTypeLabel(l10n, type),
            selected: selected == type,
            onTap: () => onChanged(type),
          ),
      ],
    );
  }
}

/// One item on Add Meal / Edit: name, kcal (from the server), quantity
/// stepper, unit dropdown and remove.
class FoodItemRow extends StatelessWidget {
  const new({
    required this.item,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final MealItemDraft item;
  final ValueChanged<MealItemDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: NcSpace.inputGap),
      padding: const EdgeInsets.all(NcSpace.buttonGap),
      decoration: BoxDecoration(
        color: nc.surface,
        borderRadius: BorderRadius.circular(NcRadius.m),
        border: Border.all(color: nc.inputFill),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.foodName, style: text.titleSmall)),
              if (item.calories != null)
                Text(
                  l10n.kcalValueShort(item.calories!),
                  style: text.bodySmall?.copyWith(color: nc.textSecondary),
                ),
              IconButton(
                tooltip: l10n.removeItem,
                icon: Icon(Icons.delete_outline, color: nc.error),
                onPressed: onRemove,
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: NcSpace.buttonGap,
            runSpacing: NcSpace.xs,
            children: [
              QuantityStepper(
                value: item.quantity,
                onChanged: (q) =>
                    onChanged(item.copyWith(quantity: q, clearCalories: true)),
              ),
              UnitDropdown(
                foodId: item.foodId,
                unitCode: item.unitCode,
                unitSize: item.unitSize,
                onChanged: (p) => onChanged(
                  item.copyWith(
                    unitCode: p.unitCode,
                    unitSize: p.size,
                    portionLabel: p.label,
                    clearCalories: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
