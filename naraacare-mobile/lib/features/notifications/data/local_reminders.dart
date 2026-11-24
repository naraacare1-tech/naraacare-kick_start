import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/system_prompt.dart';
import 'package:naraacare/features/notifications/data/notifications_api.dart';
import 'package:naraacare/features/notifications/notifications_providers.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Reminders scheduled on the phone itself (owner 2026-11-08, step 1 of
/// notifications): no server, no Firebase, works offline. The schedules and
/// toggles are the user's own from the API (GET /me/reminders and
/// /me/notification-preferences); this only mirrors them on the device:
///
/// * fixed times ("HH:MM") repeat every day at that local time;
/// * an interval repeats every N minutes from wake time to bedtime, like
///   ops.fn_due_reminders on the server;
/// * the matching preference toggle (for example hydration_reminders) must be
///   on, and the OS notification permission granted.
///
/// Times are in the profile's IANA timezone (GET /me settings.timezone).
/// Inexact alarms (a few minutes of slack) so no exact-alarm permission is
/// needed. Texts are generic (no health numbers on the lock screen, OQ-41).
/// When server push (Firebase) arrives, the device uses one or the other so
/// a reminder never comes twice.
class LocalReminders {
  new({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Water, meal and sleep reminders you set in NaraaCare',
    icon: 'ic_stat_naraacare',
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  /// Reminder type -> the preference toggle that must be on.
  static const preferenceFor = {
    'hydration': 'hydration_reminders',
    'nutrition': 'nutrition_reminders',
    'sleep': 'sleep_reminders',
    'daily_checkin': 'daily_checkin',
    'health_profile': 'health_profile_reminders',
  };

  /// Notification ids: type index x 100 + slot (at most 24 slots a type).
  static const _types = [
    'hydration',
    'nutrition',
    'sleep',
    'daily_checkin',
    'health_profile',
  ];
  static const _maxSlots = 24;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _init() async {
    if (_ready || !_supported) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_naraacare'),
        // Permission is asked from Notification Settings after the in-app
        // explainer, never at start-up.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks the OS (Android 13+ / iOS). True if notifications may be shown.
  Future<bool> requestPermission() async {
    await _init();
    return await SystemPrompt.guard(_askOs);
  }

  Future<bool> _askOs() async {
    if (!_supported) return false;
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<bool> _allowed() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final options = await ios?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  /// Replaces every scheduled reminder with [reminders] (enabled ones whose
  /// toggle in [preferences] is on). Without permission nothing is scheduled.
  Future<int> sync({
    required List<ReminderSchedule> reminders,
    required Map<String, bool> preferences,
    required String timezone,
    required String wake,
    required String bed,
    required ReminderTexts texts,
  }) async {
    await _init();
    if (!_supported) return 0;
    await _plugin.cancelAll();
    if (!await _allowed()) return 0;
    final location = _location(timezone);
    var count = 0;
    for (final r in reminders) {
      final index = _types.indexOf(r.type);
      if (index < 0 || !r.enabled) continue;
      if (!(preferences[preferenceFor[r.type]] ?? false)) continue;
      final (title, body) = texts.of(r.type);
      final slots = reminderMinutes(r, wake: wake, bed: bed);
      for (var i = 0; i < slots.length && i < _maxSlots; i++) {
        await _plugin.zonedSchedule(
          id: index * 100 + i,
          title: title,
          body: body,
          scheduledDate: _next(location, slots[i]),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: r.type,
        );
        count++;
      }
    }
    return count;
  }

  /// Sign-out: nothing of the previous user keeps ringing.
  Future<void> clear() async {
    if (!_supported) return;
    await _init();
    await _plugin.cancelAll();
  }

  static tz.Location _location(String name) {
    try {
      return tz.getLocation(name);
    } on Object {
      return tz.getLocation('Asia/Kolkata');
    }
  }

  static tz.TZDateTime _next(tz.Location location, int minuteOfDay) {
    final now = tz.TZDateTime.now(location);
    var at = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }
}

/// Minutes after midnight at which [r] fires: its fixed times, or every
/// interval_min after wake time while still before bedtime (a bedtime after
/// midnight is handled like the server: the awake span wraps).
@visibleForTesting
List<int> reminderMinutes(
  ReminderSchedule r, {
  required String wake,
  required String bed,
}) {
  int? minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h > 23 || m > 59) return null;
    return h * 60 + m;
  }

  if (r.times.isNotEmpty || r.intervalMin == null) {
    return [for (final t in r.times) ?minutes(t)];
  }
  final interval = r.intervalMin!;
  final start = minutes(wake) ?? 7 * 60;
  final end = minutes(bed) ?? 23 * 60;
  final awake = (end - start + 1440) % 1440;
  if (interval <= 0) return const [];
  return [for (var k = interval; k < awake; k += interval) (start + k) % 1440];
}

/// Localised generic reminder texts, per type.
class ReminderTexts {
  const new(this.l10n);

  final AppLocalizations l10n;

  (String, String) of(String type) => switch (type) {
    'hydration' => (l10n.reminderWaterTitle, l10n.reminderWaterBody),
    'nutrition' => (l10n.reminderMealTitle, l10n.reminderMealBody),
    'sleep' => (l10n.reminderSleepTitle, l10n.reminderSleepBody),
    'daily_checkin' => (l10n.reminderCheckinTitle, l10n.reminderCheckinBody),
    _ => (l10n.reminderProfileTitle, l10n.reminderProfileBody),
  };
}

final localRemindersProvider = Provider<LocalReminders>(
  (ref) => LocalReminders(),
);

/// Loads the user's schedules, toggles and day (wake / bedtime, timezone)
/// from the API and mirrors them on the phone. Quietly does nothing when
/// offline or not permitted: reminders are a convenience, never an error.
Future<int> syncLocalReminders(WidgetRef ref, AppLocalizations l10n) async {
  try {
    final api = ref.read(notificationsApiProvider);
    final reminders = await api.reminders();
    final preferences = await api.preferences();
    final me = await ref.read(meProvider.future);
    final settings = me.settings;
    return await ref
        .read(localRemindersProvider)
        .sync(
          reminders: reminders,
          preferences: preferences,
          timezone: (settings['timezone'] as String?) ?? 'Asia/Kolkata',
          wake: (settings['wake_local'] as String?) ?? '07:00',
          bed: (settings['sleep_start_local'] as String?) ?? '23:00',
          texts: ReminderTexts(l10n),
        );
  } on Object catch (e) {
    debugPrint('local_reminders_sync_failed ${e.runtimeType}');
    return 0;
  }
}

/// Wraps the signed-in tabs: syncs the reminders once when they first appear
/// (a fresh scope after sign-in or app start), in the background.
class LocalReminderSync extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LocalReminderSync> createState() => _LocalReminderSyncState();
}

class _LocalReminderSyncState extends ConsumerState<LocalReminderSync> {
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done) return;
    _done = true;
    unawaited(syncLocalReminders(ref, AppLocalizations.of(context)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
