import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/data/realtime_client.dart';

final circleApiProvider = Provider<CircleApi>(
  (ref) => CircleApi(ref.watch(apiClientProvider)),
);

/// The circle socket; open while any Care Circle screen watches it.
final Provider<RealtimeClient> realtimeProvider =
    Provider.autoDispose<RealtimeClient>((ref) {
      final config = ref.watch(appConfigProvider);
      final client = RealtimeClient(
        api: ref.watch(circleApiProvider),
        wsUrl: config.wsBaseUrl,
        pins: config.certPins,
      )..start();
      ref.onDispose(() => unawaited(client.close()));
      return client;
    });

/// Server events, for screens that refresh on them.
final StreamProvider<RealtimeEvent> realtimeEventsProvider =
    StreamProvider.autoDispose<RealtimeEvent>(
      (ref) => ref.watch(realtimeProvider).events,
    );

final FutureProvider<List<CircleSummary>> circlesProvider =
    FutureProvider.autoDispose<List<CircleSummary>>(
      (ref) => ref.watch(circleApiProvider).circles(),
    );

final FutureProvider<List<CircleInvite>> circleInvitesProvider =
    FutureProvider.autoDispose<List<CircleInvite>>(
      (ref) => ref.watch(circleApiProvider).invites(),
    );

final FutureProviderFamily<CircleDetail, String> circleDetailProvider =
    FutureProvider.autoDispose.family<CircleDetail, String>(
      (ref, id) => ref.watch(circleApiProvider).detail(id),
    );

final FutureProviderFamily<List<CircleMember>, String> circleMembersProvider =
    FutureProvider.autoDispose.family<List<CircleMember>, String>(
      (ref, id) => ref.watch(circleApiProvider).members(id),
    );

final FutureProviderFamily<List<FeedEvent>, String> circleFeedProvider =
    FutureProvider.autoDispose.family<List<FeedEvent>, String>(
      (ref, id) => ref.watch(circleApiProvider).feed(id),
    );

final FutureProviderFamily<List<InAppNotification>, String>
circleNotificationsProvider = FutureProvider.autoDispose
    .family<List<InAppNotification>, String>(
      (ref, id) => ref.watch(circleApiProvider).notifications(circleId: id),
    );

final FutureProviderFamily<List<MemberAvatar>, (String, String)>
memberAvatarsProvider = FutureProvider.autoDispose
    .family<List<MemberAvatar>, (String, String)>(
      (ref, ids) => ref.watch(circleApiProvider).memberAvatars(ids.$1, ids.$2),
    );

final FutureProvider<List<Connection>> connectionsProvider =
    FutureProvider.autoDispose<List<Connection>>(
      (ref) => ref.watch(circleApiProvider).connections(),
    );

final FutureProvider<List<PersonCard>> suggestionsProvider =
    FutureProvider.autoDispose<List<PersonCard>>(
      (ref) => ref.watch(circleApiProvider).suggestions(),
    );
