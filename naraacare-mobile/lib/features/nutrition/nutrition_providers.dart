import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/nutrition/data/nutrition_api.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/data/nutrition_repository.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

final nutritionApiProvider = Provider<NutritionApi>(
  (ref) => NutritionApi(ref.watch(apiClientProvider)),
);

final nutritionRepositoryProvider = Provider<NutritionRepository>(
  (ref) => NutritionRepository(
    api: ref.watch(nutritionApiProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxProvider),
  ),
);

/// STAR features are shown unlocked only for STAR users; the API enforces
/// the same rules (403 UPGRADE_REQUIRED) whatever the app shows.
final isStarProvider = Provider<bool>(
  (ref) => ref.watch(meProvider).value?.tier == 'star',
);

/// Meals waiting in the outbox ("syncing").
final pendingMealsProvider = StreamProvider<List<PendingMeal>>(
  (ref) => ref.watch(nutritionRepositoryProvider).watchPending(),
);

/// Today's summary; refreshed when queued meals finish syncing.
final dailySummaryProvider = FutureProvider<DailySummary?>((ref) {
  ref.listen(pendingMealsProvider, (previous, next) {
    final before = previous?.value?.length ?? 0;
    final now = next.value?.length ?? 0;
    if (now < before) ref.invalidateSelf();
  });
  ref.watch(remoteChangesProvider); // another device logged a meal (S14)
  return ref.watch(nutritionRepositoryProvider).dailySummary();
});

final recentMealsProvider = FutureProvider<RecentMeals>(
  (ref) => ref.watch(nutritionApiProvider).recent(),
);

final savedMealsProvider = FutureProvider<List<SavedMeal>>(
  (ref) => ref.watch(nutritionApiProvider).savedMeals(),
);

/// How the meal on the Add Meal screen was put together (POST /meals source).
enum MealSource { search, voice, barcode, saved }

class MealDraftState {
  const new({this.items = const [], this.source = MealSource.search});

  final List<MealItemDraft> items;
  final MealSource source;

  MealDraftState copyWith({List<MealItemDraft>? items, MealSource? source}) =>
      MealDraftState(items: items ?? this.items, source: source ?? this.source);
}

/// The meal being built on Add Meal (N3): at most 30 items (API limit).
class MealDraft extends Notifier<MealDraftState> {
  static const maxItems = 30;

  @override
  MealDraftState build() => const MealDraftState();

  bool add(MealItemDraft item, {MealSource? source}) {
    if (state.items.length >= maxItems) return false;
    state = state.copyWith(
      items: [...state.items, item],
      // Voice / barcode mark the meal; search keeps an earlier source.
      source: source == null || source == MealSource.search
          ? state.source
          : source,
    );
    return true;
  }

  void addAll(List<MealItemDraft> items, MealSource source) {
    final room = maxItems - state.items.length;
    state = state.copyWith(
      items: [...state.items, ...items.take(room)],
      source: state.items.isEmpty ? source : state.source,
    );
  }

  void replace(int index, MealItemDraft item) {
    final items = [...state.items]..[index] = item;
    state = state.copyWith(items: items);
  }

  void removeAt(int index) {
    final items = [...state.items]..removeAt(index);
    state = items.isEmpty
        ? const MealDraftState()
        : state.copyWith(items: items);
  }

  void clear() => state = const MealDraftState();
}

final mealDraftProvider = NotifierProvider<MealDraft, MealDraftState>(
  MealDraft.new,
);
