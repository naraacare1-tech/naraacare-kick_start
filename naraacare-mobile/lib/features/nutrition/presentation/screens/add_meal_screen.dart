import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_chip.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// N3 "Nutrition Update" (Add Meal): search (debounced 300 ms) with
/// Hinglish aliases, recent food chips, the items with quantity stepper and
/// unit, voice / barcode (STAR), View Nutrition Summary and Save Meal.
/// Digits typed in the search box are treated as a barcode (STAR).
class AddMealScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AddMealScreen> createState() => _AddMealScreenState();
}

class _AddMealScreenState extends ConsumerState<AddMealScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<FoodSearchResult>? _results;
  bool _searching = false;
  String? _error;

  static final _digits = RegExp(r'^\d{8,14}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final query = InputValidators.normalise(value);
    if (query.isEmpty || InputValidators.barcodeOrSearch(query) != null) {
      setState(() => _results = null);
      return;
    }
    if (_digits.hasMatch(query)) return; // a barcode: looked up on submit
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ref.read(nutritionApiProvider).search(query);
      if (mounted && InputValidators.normalise(_query.text) == query) {
        setState(() => _results = results);
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _submitted(String value) {
    final query = InputValidators.normalise(value);
    if (_digits.hasMatch(query)) {
      unawaited(_openBarcode(code: query));
    }
  }

  Future<void> _openBarcode({String? code}) async {
    if (!ref.read(isStarProvider)) {
      await showStarUpsell(context);
      return;
    }
    await context.push(Routes.barcodeMeal, extra: code);
  }

  Future<void> _openVoice() async {
    if (!ref.read(isStarProvider)) {
      await showStarUpsell(context);
      return;
    }
    await context.push(Routes.voiceMeal);
  }

  void _add(MealItemDraft item) {
    final added = ref.read(mealDraftProvider.notifier).add(item);
    if (!added) {
      showNcToast(
        context,
        AppLocalizations.of(context).maxMealItems,
        kind: NcToastKind.error,
      );
      return;
    }
    _query.clear();
    setState(() => _results = null);
  }

  void _addResult(FoodSearchResult r) {
    final portion = r.defaultPortion;
    if (portion == null) return;
    _add(
      MealItemDraft(
        foodId: r.foodId,
        foodName: r.name,
        quantity: 1,
        unitCode: portion.unitCode,
        unitSize: portion.size,
        portionLabel: portion.label,
        calories: r.kcalPerDefault,
      ),
    );
  }

  void _addRecent(RecentFood f) => _add(
    MealItemDraft(
      foodId: f.foodId,
      foodName: f.name,
      quantity: f.quantity,
      unitCode: f.unitCode,
      unitSize: f.unitSize,
      portionLabel: '${f.unitSize ?? ''} ${f.unitCode}'.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final draft = ref.watch(mealDraftProvider);
    final recent = ref.watch(recentMealsProvider).value?.foods ?? const [];
    final results = _results;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.addMealTitle),
        backgroundColor: nc.surface,
      ),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: NcTextField(
                  controller: _query,
                  validator: _optionalSearch,
                  maxLength: 64,
                  hint: l10n.searchFoodOrBarcodeHint,
                  prefixIcon: Icons.search,
                  textInputAction: TextInputAction.search,
                  onChanged: _changed,
                  onSubmitted: _submitted,
                ),
              ),
              IconButton(
                tooltip: l10n.voiceLogging,
                icon: const Icon(Icons.mic_none),
                onPressed: _openVoice,
              ),
              IconButton(
                tooltip: l10n.barcodeLogging,
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _openBarcode,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: NcSpace.inputGap),
            NcErrorBanner(message: _error!),
          ],
          if (_searching) const LinearProgressIndicator(),
          if (results != null)
            _SearchResults(results: results, onTap: _addResult)
          else if (recent.isNotEmpty) ...[
            const SizedBox(height: NcSpace.cardGap),
            Text(
              l10n.recentChips,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: NcSpace.inputGap),
            Wrap(
              spacing: NcSpace.inputGap,
              runSpacing: NcSpace.inputGap,
              children: [
                for (final f in recent)
                  NcChip(label: f.name, onTap: () => _addRecent(f)),
              ],
            ),
          ],
          const SizedBox(height: NcSpace.sectionGap),
          Text(
            l10n.addItemsCount(draft.items.length),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: NcSpace.inputGap),
          if (draft.items.isEmpty)
            Text(l10n.emptyMeal, style: TextStyle(color: nc.textSecondary)),
          for (var i = 0; i < draft.items.length; i++)
            FoodItemRow(
              key: ValueKey('item-$i-${draft.items[i].foodId}'),
              item: draft.items[i],
              onChanged: (item) =>
                  ref.read(mealDraftProvider.notifier).replace(i, item),
              onRemove: () => ref.read(mealDraftProvider.notifier).removeAt(i),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NcButton(
                label: l10n.viewNutritionSummary,
                variant: NcButtonVariant.secondary,
                onPressed: draft.items.isEmpty
                    ? null
                    : () => context.push(Routes.mealSummary),
              ),
              const SizedBox(height: NcSpace.inputGap),
              NcButton(
                label: l10n.saveMealButton,
                onPressed: draft.items.isEmpty
                    ? null
                    : () => showSaveMealSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The search box: empty is fine; anything typed must pass the search or
/// barcode rules (doc 07 4.3).
ValidationError? _optionalSearch(String value) =>
    value.trim().isEmpty ? null : InputValidators.barcodeOrSearch(value);

class _SearchResults extends StatelessWidget {
  const new({required this.results, required this.onTap});

  final List<FoodSearchResult> results;
  final ValueChanged<FoodSearchResult> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NcSpace.cardGap),
        child: Text(
          l10n.noFoodsFound,
          style: TextStyle(color: nc.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        for (final r in results)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r.name),
            subtitle: Text(
              [
                if (r.defaultPortion != null) r.defaultPortion!.display,
                if (r.matchedAlias != null) r.matchedAlias!,
              ].join(' · '),
            ),
            trailing: Text(l10n.kcalValueShort(r.kcalPerDefault)),
            onTap: () => onTap(r),
          ),
      ],
    );
  }
}

/// Save Meal sheet: meal type (suggested by the time of day), optional
/// "also add to Saved Meals" with a name, then POST /meals.
Future<void> showSaveMealSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.saveMealButton,
    builder: (context) => const _SaveMealSheet(),
  );
}

class _SaveMealSheet extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_SaveMealSheet> createState() => _SaveMealSheetState();
}

class _SaveMealSheetState extends ConsumerState<_SaveMealSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late String _mealType = suggestMealType(DateTime.now());
  bool _favourite = false;
  bool _busy = false;
  String? _error;

  static final Validator _nameValidator = InputValidators.shortText(max: 60);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final draft = ref.read(mealDraftProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(nutritionRepositoryProvider)
          .logMeal(
            items: draft.items,
            mealType: _mealType,
            source: draft.source.name,
          );
      if (_favourite && !result.queued) {
        await ref
            .read(nutritionApiProvider)
            .saveMealTemplate(
              InputValidators.normalise(_name.text),
              draft.items,
            );
        ref.invalidate(savedMealsProvider);
      }
      ref
        ..invalidate(dailySummaryProvider)
        ..invalidate(recentMealsProvider)
        ..read(mealDraftProvider.notifier).clear();
      if (!mounted) return;
      showNcToast(context, result.queued ? l10n.mealQueued : l10n.mealSaved);
      Navigator.of(context).pop();
      context.go(Routes.home);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'DAILY_LIMIT_REACHED') {
        Navigator.of(context).pop();
        await showMealLimitSheet(context, e.limit ?? 4);
        return;
      }
      if (e.code == ApiError.upgradeRequired) {
        Navigator.of(context).pop();
        await showStarUpsell(context);
        return;
      }
      setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(mealDraftProvider).items;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in items)
            Text(
              '${formatQuantity(i.quantity)} × ${i.portionLabel} · '
              '${i.foodName}',
            ),
          const SizedBox(height: NcSpace.cardGap),
          Text(
            l10n.mealTypeLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: NcSpace.inputGap),
          MealTypeChips(
            selected: _mealType,
            onChanged: (t) => setState(() => _mealType = t),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.alsoSaveFavourite),
            value: _favourite,
            onChanged: (v) => setState(() => _favourite = v),
          ),
          if (_favourite)
            NcTextField(
              controller: _name,
              validator: _nameValidator,
              maxLength: 60,
              label: l10n.savedMealNameLabel,
              hint: l10n.savedMealNameHint,
            ),
          if (_error != null) ...[
            const SizedBox(height: NcSpace.inputGap),
            NcErrorBanner(message: _error!),
          ],
          const SizedBox(height: NcSpace.cardGap),
          NcButton(
            label: l10n.saveMealButton,
            loading: _busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// DAILY_LIMIT_REACHED: STANDARD gets the STAR upsell, STAR a friendly note.
Future<void> showMealLimitSheet(BuildContext context, int limit) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.limitTitle,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final star = ref.watch(isStarProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              star ? l10n.limitBodyStar(limit) : l10n.limitBodyStandard(limit),
            ),
            const SizedBox(height: NcSpace.cardGap),
            if (!star) ...[
              NcButton(
                label: l10n.upsellTitle,
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(showStarUpsell(context));
                },
              ),
              const SizedBox(height: NcSpace.inputGap),
            ],
            NcButton(
              label: l10n.gotIt,
              variant: star ? NcButtonVariant.primary : NcButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    ),
  );
}
