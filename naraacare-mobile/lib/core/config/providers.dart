import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/config/app_config.dart';

/// Overridden in `bootstrap` with the validated config for the running flavor.
/// Throws away every provider (all cached user data, open sockets, timers)
/// and starts the app again from the splash. Overridden in `bootstrap`;
/// called after sign-out so the next account never sees the previous one's
/// state. A no-op in tests.
final restartAppProvider = Provider<void Function()>((ref) => () {});

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
