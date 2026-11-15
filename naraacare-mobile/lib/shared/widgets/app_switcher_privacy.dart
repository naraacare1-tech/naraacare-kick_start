import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Covers every screen with an opaque brand cover while the app is inactive
/// or in the background, so the app-switcher snapshot shows no health data
/// (doc 07 SEC-5.5).
class AppSwitcherPrivacy extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<AppSwitcherPrivacy> createState() => _AppSwitcherPrivacyState();
}

class _AppSwitcherPrivacyState extends State<AppSwitcherPrivacy>
    with WidgetsBindingObserver {
  bool _covered = false;

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
    final cover = state != AppLifecycleState.resumed;
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: ColoredBox(
              key: const Key('app-switcher-cover'),
              color: nc.surface,
              child: Center(
                child: Text(
                  AppLocalizations.of(context).appName,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: NcTypeScale.fontFamily,
                    fontSize: NcTypeScale.h2,
                    color: nc.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
