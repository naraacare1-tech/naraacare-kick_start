import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/profile/data/profile_tab_api.dart';

final profileTabApiProvider = Provider<ProfileTabApi>(
  (ref) => ProfileTabApi(ref.watch(apiClientProvider)),
);

/// The streak for one month (null = the current month).
final FutureProviderFamily<StreakInfo, DateTime?> streakProvider =
    FutureProvider.autoDispose.family<StreakInfo, DateTime?>(
      (ref, month) => ref.watch(profileTabApiProvider).streak(month: month),
    );

/// The user's own notifications (all circles and personal ones).
final FutureProvider<List<InAppNotification>> myNotificationsProvider =
    FutureProvider.autoDispose<List<InAppNotification>>(
      (ref) => ref.watch(circleApiProvider).notifications(),
    );

/// Reports of the last 12 months (newest first).
final FutureProvider<List<ReportJob>> reportsProvider =
    FutureProvider.autoDispose<List<ReportJob>>(
      (ref) => ref.watch(profileTabApiProvider).reports(),
    );

final FutureProvider<(List<Faq>, SupportContact)> supportInfoProvider =
    FutureProvider.autoDispose<(List<Faq>, SupportContact)>(
      (ref) => ref.watch(profileTabApiProvider).faqs(),
    );
