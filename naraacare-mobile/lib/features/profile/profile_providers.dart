import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';
import 'package:naraacare/features/profile/data/reference_data.dart';

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref.watch(apiClientProvider)),
);

final referenceRepositoryProvider = Provider<ReferenceRepository>(
  (ref) => ReferenceRepository(
    api: ref.watch(apiClientProvider),
    db: ref.watch(databaseProvider),
  ),
);

/// Labels for activity levels, goals, conditions and body types.
final referenceDataProvider = FutureProvider<ReferenceData>(
  (ref) => ref.watch(referenceRepositoryProvider).load(),
);

/// The signed-in user (GET /me). Screens invalidate it after a change.
final meProvider = FutureProvider<Me>(
  (ref) => ref.watch(profileApiProvider).me(),
);
