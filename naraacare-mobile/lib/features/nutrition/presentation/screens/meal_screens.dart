import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/screens/add_meal_screen.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_empty_state.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:uuid/uuid.dart';

/// The dry run of the current draft (POST /meals?dry_run=true): totals come
/// from the server and nothing is saved or counted toward the limit.
final FutureProvider<MealPreview> _previewProvider =
    FutureProvider.autoDispose<MealPreview>((ref) {
      final draft = ref.watch(mealDraftProvider);
      final api = ref.watch(nutritionApiProvider);
      return api.preview(
        api.mealBody(
          clientEntryId: const Uuid().v7(),
          loggedAt: DateTime.now(),
          mealType: suggestMealType(DateTime.now()),
          source: draft.source.name,
          items: draft.items,
        ),
      );
    });

/// Nutrition Summary of the meal being built (Figma "Nutrition Update-3"):
/// calories and the tier's nutrients, the STAR upsell, then Save Meal.
class MealSummaryScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final preview = ref.watch(_previewProvider);
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.nutritionSummaryTitle),
        backgroundColor: nc.surface,
      ),
      body: switch (preview) {
        AsyncData(:final value) => ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Text(
              l10n.kcalValueShort(value.calories),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: NcSpace.cardGap),
            NutrientList(view: value.totals),
            const SizedBox(height: NcSpace.cardGap),
            UpsellCard(lockedCount: value.totals.lockedCount),
          ],
        ),
        AsyncError(:final error) => Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: NcErrorBanner(
            message: error is ApiError
                ? featureErrorMessage(l10n, error)
                : l10n.errorGeneric,
            actionLabel: l10n.actionRetry,
            onAction: () => ref.invalidate(_previewProvider),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: NcButton(
            label: l10n.saveMealButton,
            onPressed: () => showSaveMealSheet(context),
          ),
        ),
      ),
    );
  }
}

/// N9 Recent Updates: Last 2 Updates (editable) and older entries, plus
/// Saved Meals; STAR can open the meal-by-meal breakdown.
class RecentMealsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(
          title: Text(l10n.recentUpdates),
          backgroundColor: nc.surface,
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.lastTwoUpdates),
              Tab(text: l10n.savedMealsTab),
            ],
          ),
        ),
        body: const TabBarView(children: [_RecentList(), _SavedList()]),
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final pending = ref.watch(pendingMealsProvider).value ?? const [];
    return switch (ref.watch(recentMealsProvider)) {
      AsyncData(:final value) =>
        value.meals.isEmpty && pending.isEmpty
            ? NcEmptyState(title: l10n.noRecentMeals)
            : RefreshIndicator(
                onRefresh: () => ref.refresh(recentMealsProvider.future),
                child: ListView(
                  padding: EdgeInsets.all(nc.screenPadding),
                  children: [
                    for (final p in pending)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.cloud_upload_outlined),
                          title: Text(p.items.join(', ')),
                          subtitle: Text(l10n.syncingLabel),
                        ),
                      ),
                    for (final meal in value.meals) _MealCard(meal: meal),
                  ],
                ),
              ),
      AsyncError(:final error) => Padding(
        padding: EdgeInsets.all(nc.screenPadding),
        child: NcErrorBanner(
          message: error is ApiError
              ? featureErrorMessage(l10n, error)
              : l10n.errorGeneric,
          actionLabel: l10n.actionRetry,
          onAction: () => ref.invalidate(recentMealsProvider),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _MealCard extends ConsumerWidget {
  const new({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final time = TimeOfDay.fromDateTime(meal.loggedAt.toLocal())
        .format(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NcSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${mealTypeLabel(l10n, meal.mealType)} · $time',
                    style: text.titleSmall,
                  ),
                ),
                Text(
                  l10n.kcalValueShort(meal.calories),
                  style: text.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: NcSpace.xs),
            for (final i in meal.items)
              Text(
                '${formatQuantity(i.quantity)} ${i.unitSize ?? ''} '
                '${i.unitCode} · ${i.foodName}',
                style: text.bodySmall,
              ),
            const SizedBox(height: NcSpace.inputGap),
            Row(
              children: [
                if (meal.editable)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.editYourEntry),
                    onPressed: () => context.push(Routes.editMeal, extra: meal),
                  )
                else
                  Expanded(
                    child: Text(
                      '${l10n.otherEntry} · ${l10n.onlyLastTwoEditable}',
                      style: text.bodySmall?.copyWith(color: nc.textSecondary),
                    ),
                  ),
                if (meal.editable) const Spacer(),
                TextButton.icon(
                  icon: ref.watch(isStarProvider)
                      ? const Icon(Icons.pie_chart_outline)
                      : const NcStarBadge(),
                  label: Text(l10n.mealBreakdown),
                  onPressed: () => _breakdown(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _breakdown(BuildContext context, WidgetRef ref) async {
    if (!ref.read(isStarProvider)) {
      await showStarUpsell(context);
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      final breakdown = await ref
          .read(nutritionApiProvider)
          .breakdown(meal.mealId);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NcSpace.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.macroSplit(
                    breakdown.macroPct['carbohydrates'] ?? 0,
                    breakdown.macroPct['protein'] ?? 0,
                    breakdown.macroPct['fat'] ?? 0,
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: NcSpace.inputGap),
                NutrientList(view: breakdown.totals),
              ],
            ),
          ),
        ),
      );
    } on ApiError catch (e) {
      if (!context.mounted) return;
      if (e.code == ApiError.upgradeRequired) {
        await showStarUpsell(context);
      } else {
        showNcToast(
          context,
          featureErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    }
  }
}

class _SavedList extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return switch (ref.watch(savedMealsProvider)) {
      AsyncData(:final value) =>
        value.isEmpty
            ? NcEmptyState(title: l10n.noSavedMeals)
            : ListView(
                padding: EdgeInsets.all(nc.screenPadding),
                children: [
                  for (final saved in value)
                    Card(
                      child: ListTile(
                        title: Text(saved.name),
                        subtitle: Text(l10n.mealItemsCount(saved.items.length)),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: l10n.delete,
                              icon: Icon(Icons.delete_outline, color: nc.error),
                              onPressed: () async {
                                await ref
                                    .read(nutritionApiProvider)
                                    .deleteSavedMeal(saved.id);
                                ref.invalidate(savedMealsProvider);
                              },
                            ),
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(mealDraftProvider.notifier)
                                    .addAll(saved.items, MealSource.saved);
                                context.pushReplacement(Routes.addMeal);
                              },
                              child: Text(l10n.useSavedMeal),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      AsyncError() => Padding(
        padding: EdgeInsets.all(nc.screenPadding),
        child: NcErrorBanner(
          message: l10n.errorGeneric,
          actionLabel: l10n.actionRetry,
          onAction: () => ref.invalidate(savedMealsProvider),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// N10 Edit your entry: one of the last 2 meals. Change quantities, units or
/// remove items, then Update Meal (If-Match version); or delete it.
class EditMealScreen extends ConsumerStatefulWidget {
  const new({required this.meal, super.key});

  final Meal meal;

  @override
  ConsumerState<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends ConsumerState<EditMealScreen> {
  late List<MealItemDraft> _items = [
    for (final i in widget.meal.items)
      MealItemDraft(
        foodId: i.foodId,
        foodName: i.foodName,
        quantity: i.quantity,
        unitCode: i.unitCode,
        unitSize: i.unitSize,
        portionLabel: '${i.unitSize ?? ''} ${i.unitCode}'.trim(),
        calories: i.calories,
      ),
  ];
  late String _mealType = widget.meal.mealType;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String done) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref
        ..invalidate(dailySummaryProvider)
        ..invalidate(recentMealsProvider);
      if (!mounted) return;
      showNcToast(context, done);
      context.pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == ApiError.versionConflict) {
        // The server copy wins (changed on another device): reload the list.
        ref.invalidate(recentMealsProvider);
        showNcToast(context, l10n.errorConflict, kind: NcToastKind.error);
        context.pop();
        return;
      }
      setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update() => _run(
    () => ref
        .read(nutritionApiProvider)
        .updateMeal(
          widget.meal.mealId,
          widget.meal.version,
          mealType: _mealType,
          items: _items,
        ),
    AppLocalizations.of(context).entryUpdated,
  );

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEntry),
        content: Text(l10n.deleteEntryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref
          .read(nutritionApiProvider)
          .deleteMeal(widget.meal.mealId, widget.meal.version),
      l10n.entryDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.editYourEntry),
        backgroundColor: nc.surface,
        actions: [
          IconButton(
            tooltip: l10n.deleteEntry,
            icon: Icon(Icons.delete_outline, color: nc.error),
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Text(
            l10n.onlyLastTwoEditable,
            style: TextStyle(color: nc.textSecondary),
          ),
          const SizedBox(height: NcSpace.cardGap),
          MealTypeChips(
            selected: _mealType,
            onChanged: (t) => setState(() => _mealType = t),
          ),
          const SizedBox(height: NcSpace.cardGap),
          for (var i = 0; i < _items.length; i++)
            FoodItemRow(
              key: ValueKey('edit-$i-${_items[i].foodId}'),
              item: _items[i],
              onChanged: (item) =>
                  setState(() => _items = [..._items]..[i] = item),
              onRemove: _items.length == 1
                  ? _delete
                  : () => setState(() => _items = [..._items]..removeAt(i)),
            ),
          if (_error != null) NcErrorBanner(message: _error!),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: NcButton(
            label: l10n.updateMealButton,
            loading: _busy,
            onPressed: _update,
          ),
        ),
      ),
    );
  }
}

/// Exposed for tests: unawaited navigation helpers.
void openRecentMeals(BuildContext context) =>
    unawaited(context.push(Routes.recentMeals));
