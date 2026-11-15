import 'package:naraacare/core/network/api_client.dart';

/// Devices, notification preferences and reminder schedules (doc 04
/// section 2.7).
class NotificationsApi {
  const new(this.api);

  final ApiClient api;

  /// The app version Flutter passes at build time (no package needed).
  static const appVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '1.0.0',
  );

  Future<void> registerDevice({
    required String installationId,
    required String platform,
    required String pushToken,
  }) => api.post(
    'devices',
    body: {
      'installation_id': installationId,
      'platform': platform,
      'push_token': pushToken,
      'app_version': appVersion,
    },
  );

  Future<Map<String, bool>> preferences() async {
    final body =
        (await api.get('me/notification-preferences'))! as Map<String, dynamic>;
    return body.map((k, v) => MapEntry(k, v as bool));
  }

  /// PUT replaces all 12 toggles.
  Future<void> setPreferences(Map<String, bool> values) =>
      api.put('me/notification-preferences', body: values);

  Future<List<ReminderSchedule>> reminders() async {
    final body = (await api.get('me/reminders'))! as Map<String, dynamic>;
    return [
      for (final r in (body['reminders'] as List).cast<Map<String, dynamic>>())
        ReminderSchedule.fromJson(r),
    ];
  }

  Future<List<ReminderSchedule>> setReminders(
    List<ReminderSchedule> items,
  ) async {
    final body =
        (await api.put(
              'me/reminders',
              body: {
                'reminders': [for (final r in items) r.toJson()],
              },
            ))!
            as Map<String, dynamic>;
    return [
      for (final r in (body['reminders'] as List).cast<Map<String, dynamic>>())
        ReminderSchedule.fromJson(r),
    ];
  }
}

/// One reminder type: local times ("HH:MM") or an interval from wake time.
class ReminderSchedule {
  const new({
    required this.type,
    required this.enabled,
    required this.times,
    this.intervalMin,
  });

  factory fromJson(Map<String, dynamic> json) => ReminderSchedule(
    type: json['type'] as String,
    enabled: json['enabled'] as bool,
    times: (json['times'] as List).cast<String>(),
    intervalMin: json['interval_min'] as int?,
  );

  final String type;
  final bool enabled;
  final List<String> times;
  final int? intervalMin;

  ReminderSchedule copyWith({bool? enabled, List<String>? times}) =>
      ReminderSchedule(
        type: type,
        enabled: enabled ?? this.enabled,
        times: times ?? this.times,
        intervalMin: intervalMin,
      );

  Map<String, Object?> toJson() => {
    'type': type,
    'enabled': enabled,
    'times': times,
    'interval_min': ?intervalMin,
  };
}
