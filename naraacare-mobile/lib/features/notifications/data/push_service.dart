import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/notifications/data/local_reminders.dart';
import 'package:naraacare/features/notifications/notifications_providers.dart';

/// Push notifications behind an interface so the app does not depend on a
/// Firebase project to build or test. Step 1 (owner 2026-11-08):
/// [LocalPushService] asks the OS permission and reminders are scheduled on
/// the phone (local_reminders.dart); it has no push token yet. Step 2 adds
/// firebase_messaging when the Firebase projects exist (owner action).
abstract interface class PushService {
  /// Asks the OS for permission (after the in-app explainer). True if granted.
  Future<bool> requestPermission();

  /// The current FCM token, or null when push is unavailable.
  Future<String?> token();
}

class DisabledPushService implements PushService {
  const new();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> token() async => null;
}

/// Step 1: the OS notification permission through flutter_local_notifications;
/// no server push token until Firebase is added.
class LocalPushService implements PushService {
  const new(this.reminders);

  final LocalReminders reminders;

  @override
  Future<bool> requestPermission() => reminders.requestPermission();

  @override
  Future<String?> token() async => null;
}

final pushServiceProvider = Provider<PushService>(
  (ref) => LocalPushService(ref.watch(localRemindersProvider)),
);

/// Asks the OS permission (after the in-app explainer). With a push token
/// (step 2, Firebase) the device is also registered: POST /devices, the API
/// encrypts the token. Returns false only when permission was refused.
Future<bool> enablePush(WidgetRef ref) async {
  final push = ref.read(pushServiceProvider);
  if (!await push.requestPermission()) return false;
  final token = await push.token();
  if (token == null) return true;
  await ref
      .read(notificationsApiProvider)
      .registerDevice(
        installationId: await ref.read(secureStorageProvider).installationId(),
        platform: Platform.isIOS ? 'ios' : 'android',
        pushToken: token,
      );
  return true;
}
