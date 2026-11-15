import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/sleep/data/sleep_data.dart';

final sleepApiProvider = Provider<SleepApi>(
  (ref) => SleepApi(ref.watch(apiClientProvider)),
);

final sleepRepositoryProvider = Provider<SleepRepository>(
  (ref) => SleepRepository(
    api: ref.watch(sleepApiProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxProvider),
  ),
);

/// Today's sleep (STAR); only watched when the user is STAR.
final sleepSummaryProvider = FutureProvider<SleepSummary>((ref) {
  ref.watch(remoteChangesProvider); // another device logged sleep (S14)
  return ref.watch(sleepRepositoryProvider).summary();
});
