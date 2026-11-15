import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_protector/screen_protector.dart';

/// Turns screenshot/recording protection on while at least one guarded screen
/// is visible (doc 07 SEC-5.5, OQ-50): Android FLAG_SECURE, iOS secure
/// overlay. Used on auth, OTP, password, account, deletion and export screens.
abstract interface class ScreenProtection {
  Future<void> enable();
  Future<void> disable();
}

class PlatformScreenProtection implements ScreenProtection {
  const new();

  @override
  Future<void> enable() => _safely(ScreenProtector.preventScreenshotOn);

  @override
  Future<void> disable() => _safely(ScreenProtector.preventScreenshotOff);

  static Future<void> _safely(Future<void> Function() call) async {
    try {
      await call();
    } on MissingPluginException {
      // tests and desktop: nothing to protect
    } on PlatformException {
      // best effort; the overlay below still hides app-switcher snapshots
    }
  }
}

class ScreenGuard extends StatefulWidget {
  const new({
    required this.child,
    super.key,
    this.protection = const PlatformScreenProtection(),
  });

  final Widget child;
  final ScreenProtection protection;

  /// Number of guarded screens currently mounted (nested routes).
  static int active = 0;

  @override
  State<ScreenGuard> createState() => _ScreenGuardState();
}

class _ScreenGuardState extends State<ScreenGuard> {
  @override
  void initState() {
    super.initState();
    if (ScreenGuard.active++ == 0) unawaited(widget.protection.enable());
  }

  @override
  void dispose() {
    if (--ScreenGuard.active == 0) unawaited(widget.protection.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
