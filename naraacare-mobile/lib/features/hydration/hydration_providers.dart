import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:naraacare/features/hydration/data/hydration_api.dart';
import 'package:naraacare/features/hydration/data/hydration_models.dart';
import 'package:naraacare/features/hydration/data/hydration_repository.dart';

final hydrationApiProvider = Provider<HydrationApi>(
  (ref) => HydrationApi(ref.watch(apiClientProvider)),
);

final hydrationRepositoryProvider = Provider<HydrationRepository>(
  (ref) => HydrationRepository(
    api: ref.watch(hydrationApiProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxProvider),
  ),
);

/// Effective mL of drinks waiting in the outbox (optimistic display).
final pendingIntakeMlProvider = StreamProvider<int>(
  (ref) => ref.watch(hydrationRepositoryProvider).watchPendingMl(),
);

/// Today's status; refreshed when queued drinks finish syncing, and shown
/// with the queued mL added (the server value replaces it after sync).
final hydrationStatusProvider = FutureProvider<HydrationStatus>((ref) {
  ref.listen(pendingIntakeMlProvider, (previous, next) {
    if ((next.value ?? 0) < (previous?.value ?? 0)) ref.invalidateSelf();
  });
  ref.watch(remoteChangesProvider); // another device logged a drink (S14)
  return ref.watch(hydrationRepositoryProvider).status();
});

final shownHydrationProvider = Provider<AsyncValue<HydrationStatus>>((ref) {
  final pending = ref.watch(pendingIntakeMlProvider).value ?? 0;
  return ref
      .watch(hydrationStatusProvider)
      .whenData((s) => pending == 0 ? s : s.withPending(pending));
});

final drinkCatalogueProvider = FutureProvider<DrinkCatalogue>(
  (ref) => ref.watch(hydrationApiProvider).drinks(),
);

final todaysIntakesProvider = FutureProvider<List<Intake>>(
  (ref) => ref
      .watch(hydrationApiProvider)
      .intakes(HydrationRepository.today(const SystemClock())),
);

final todaysWorkoutsProvider = FutureProvider<List<Workout>>(
  (ref) => ref
      .watch(hydrationApiProvider)
      .workouts(HydrationRepository.today(const SystemClock())),
);
