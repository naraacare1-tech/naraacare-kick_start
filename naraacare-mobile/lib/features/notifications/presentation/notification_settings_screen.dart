import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/notifications/data/local_reminders.dart';
import 'package:naraacare/features/notifications/data/notifications_api.dart';
import 'package:naraacare/features/notifications/data/push_service.dart';
import 'package:naraacare/features/notifications/notifications_providers.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// Explains why NaraaCare sends notifications before the OS prompt (the OS
/// only asks once). Returns true when the user wants to continue.
Future<bool> showPermissionExplainer(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showNcBottomSheet<bool>(
    context: context,
    title: l10n.notificationsExplainerTitle,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.notificationsExplainerBody),
        const SizedBox(height: NcSpace.cardGap),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.allowNotifications),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.notNow),
        ),
      ],
    ),
  );
  return ok ?? false;
}

String preferenceLabel(AppLocalizations l10n, String key) => switch (key) {
  'goal_completions' => l10n.prefGoalCompletions,
  'streak_milestones' => l10n.prefStreakMilestones,
  'health_insights' => l10n.prefHealthInsights,
  'hydration_reminders' => l10n.prefHydrationReminders,
  'nutrition_reminders' => l10n.prefNutritionReminders,
  'sleep_reminders' => l10n.prefSleepReminders,
  'daily_checkin' => l10n.prefDailyCheckin,
  'health_profile_reminders' => l10n.prefHealthProfile,
  'connection_requests' => l10n.prefConnectionRequests,
  'connection_activity' => l10n.prefConnectionActivity,
  'reports_ready' => l10n.prefReportsReady,
  _ => l10n.prefSubscriptionPayments,
};

String reminderLabel(AppLocalizations l10n, String type) => switch (type) {
  'hydration' => l10n.avatarWater,
  'nutrition' => l10n.avatarFood,
  'sleep' => l10n.avatarSleep,
  'daily_checkin' => l10n.prefDailyCheckin,
  _ => l10n.prefHealthProfile,
};

/// [all] with the schedule of [type] replaced by [change] of it.
List<ReminderSchedule> _with(
  List<ReminderSchedule> all,
  String type,
  ReminderSchedule Function(ReminderSchedule) change,
) => all.map((x) => x.type == type ? change(x) : x).toList();

const _preferenceOrder = [
  'goal_completions',
  'streak_milestones',
  'health_insights',
  'hydration_reminders',
  'nutrition_reminders',
  'sleep_reminders',
  'daily_checkin',
  'health_profile_reminders',
  'connection_requests',
  'connection_activity',
  'reports_ready',
  'subscription_payments',
];

/// "Notification Settings" (reminders part, S09): the 12 toggles and the
/// reminder schedules. Times are picked with the system time picker (no
/// text entry); the server stores and fires them in the user's local time.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _askedPermission = false;

  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          featureErrorMessage(AppLocalizations.of(context), e),
          kind: NcToastKind.error,
        );
      }
    }
  }

  Future<void> _maybeAskPermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    if (!await showPermissionExplainer(context)) return;
    final enabled = await enablePush(ref);
    if (!enabled && mounted) {
      showNcToast(
        context,
        AppLocalizations.of(context).pushUnavailable,
        kind: NcToastKind.info,
      );
    }
  }

  Future<void> _togglePreference(Map<String, bool> all, String key, bool v) =>
      _guard(() async {
        await ref.read(notificationsApiProvider).setPreferences({
          ...all,
          key: v,
        });
        ref.invalidate(notificationPreferencesProvider);
        if (mounted) await _syncPhone();
      });

  /// Mirrors the saved schedules on the phone (local reminders, step 1).
  Future<void> _syncPhone() =>
      syncLocalReminders(ref, AppLocalizations.of(context));

  Future<void> _saveReminders(List<ReminderSchedule> items) => _guard(() async {
    await ref.read(notificationsApiProvider).setReminders(items);
    ref.invalidate(remindersProvider);
    if (mounted) await _syncPhone();
  });

  Future<void> _addTime(List<ReminderSchedule> all, ReminderSchedule r) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || r.times.length >= 12) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    if (r.times.contains(hhmm)) return;
    await _saveReminders(
      _with(all, r.type, (x) => x.copyWith(times: [...x.times, hhmm]..sort())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final prefs = ref.watch(notificationPreferencesProvider);
    final reminders = ref.watch(remindersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsReminders)),
      backgroundColor: nc.surface,
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Text(l10n.remindersSection, style: text.titleSmall),
          ...reminders.when(
            loading: () => [const LinearProgressIndicator()],
            error: (_, _) => [Text(l10n.settingsUnavailable)],
            data: (all) => [
              for (final r in all)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(reminderLabel(l10n, r.type)),
                      subtitle: Text(
                        r.intervalMin != null && r.times.isEmpty
                            ? l10n.everyMinutes(r.intervalMin!)
                            : r.times.join(' · '),
                      ),
                      value: r.enabled,
                      onChanged: (v) async {
                        if (v) await _maybeAskPermission();
                        await _saveReminders(
                          _with(all, r.type, (x) => x.copyWith(enabled: v)),
                        );
                      },
                    ),
                    if (r.enabled && r.intervalMin == null)
                      Wrap(
                        spacing: NcSpace.inputGap,
                        children: [
                          for (final t in r.times)
                            InputChip(
                              label: Text(t),
                              onDeleted: r.times.length == 1
                                  ? null
                                  : () => _saveReminders(
                                      _with(
                                        all,
                                        r.type,
                                        (x) => x.copyWith(
                                          times: [...x.times]..remove(t),
                                        ),
                                      ),
                                    ),
                            ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.add,
                              size: NcSize.iconSmall,
                            ),
                            label: Text(l10n.addTime),
                            onPressed: () => unawaited(_addTime(all, r)),
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: NcSpace.sectionGap),
          Text(l10n.notificationTypesSection, style: text.titleSmall),
          ...prefs.when(
            loading: () => [const LinearProgressIndicator()],
            error: (_, _) => [Text(l10n.settingsUnavailable)],
            data: (all) => [
              for (final key in _preferenceOrder)
                if (all.containsKey(key))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(preferenceLabel(l10n, key)),
                    value: all[key]!,
                    onChanged: (v) => _togglePreference(all, key, v),
                  ),
            ],
          ),
          const SizedBox(height: NcSpace.cardGap),
          Text(
            l10n.quietHoursNote,
            style: text.bodySmall?.copyWith(color: nc.textSecondary),
          ),
        ],
      ),
    );
  }
}
