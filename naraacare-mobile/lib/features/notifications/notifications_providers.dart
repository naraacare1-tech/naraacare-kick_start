import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/notifications/data/notifications_api.dart';

final notificationsApiProvider = Provider<NotificationsApi>(
  (ref) => NotificationsApi(ref.watch(apiClientProvider)),
);

final notificationPreferencesProvider = FutureProvider<Map<String, bool>>(
  (ref) => ref.watch(notificationsApiProvider).preferences(),
);

final remindersProvider = FutureProvider<List<ReminderSchedule>>(
  (ref) => ref.watch(notificationsApiProvider).reminders(),
);
