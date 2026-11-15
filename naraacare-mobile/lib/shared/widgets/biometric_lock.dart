import 'dart:async';

import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/biometric_gate.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// Locks the app after more than a minute in the background when the user
/// turned the biometric lock on (doc 07 SEC-5.6). Biometrics with the device
/// passcode as fallback.
class BiometricLock extends StatefulWidget {
  const new({
    required this.enabled,
    required this.authenticator,
    required this.child,
    super.key,
    this.clock = const SystemClock(),
  });

  final bool enabled;
  final Authenticator authenticator;
  final Clock clock;
  final Widget child;

  @override
  State<BiometricLock> createState() => _BiometricLockState();
}

class _BiometricLockState extends State<BiometricLock>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _locked = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt ??= widget.clock.now();
    } else if (state == AppLifecycleState.resumed) {
      final lock = BiometricPolicy.shouldLock(
        enabled: widget.enabled,
        backgroundedAt: _backgroundedAt,
        now: widget.clock.now(),
      );
      _backgroundedAt = null;
      if (lock) {
        setState(() => _locked = true);
        unawaited(_unlock());
      }
    }
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    final reason = AppLocalizations.of(context).biometricReason;
    final ok = await widget.authenticator.authenticate(reason);
    _asking = false;
    if (mounted && ok) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final nc = context.nc;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            key: const Key('biometric-lock'),
            color: nc.surface,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(nc.screenPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: NcSize.icon * 2,
                      color: nc.primary,
                    ),
                    const SizedBox(height: NcSpace.sectionGap),
                    NcButton(
                      label: AppLocalizations.of(context).biometricUnlock,
                      onPressed: _unlock,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
