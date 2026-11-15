import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';

/// A1 Splash, every app start (owner 2026-11-08): the brand animation
/// (assets/brand/splash.json: a drop falls, floods the screen blue, then the
/// logo and "Naraa Care" appear). The session check ([onStart]: stored
/// tokens -> silent refresh) runs while it plays; [onFinished] tells the
/// router the animation is over, and it holds the splash until then.
/// A deep link (invite) opened over the splash is not delayed.
/// With the system "remove animations" setting the last frame is shown.
class SplashScreen extends StatefulWidget {
  const new({required this.onStart, required this.onFinished, super.key});

  final Future<void> Function() onStart;
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// The animation's last frame colour (its "flood" layer), so a slow session
/// check after the animation never flashes white.
const _flood = Color(0xFF35AFEF);

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  final _played = Completer<void>();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
      _played.complete();
    }
    unawaited(widget.onStart());
    unawaited(_played.future.then((_) => widget.onFinished()));
  }

  void _loaded(LottieComposition composition) {
    if (_played.isCompleted) return;
    _anim.duration = composition.duration;
    unawaited(
      _anim.forward().whenComplete(() {
        if (!_played.isCompleted) _played.complete();
      }),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Semantics(
      label: AppLocalizations.of(context).appName,
      child: SizedBox.expand(
        child: Lottie.asset(
          'assets/brand/splash.json',
          controller: _anim,
          fit: BoxFit.cover,
          onLoaded: _loaded,
          // A broken asset must never block start-up.
          errorBuilder: (context, _, _) {
            if (!_played.isCompleted) _played.complete();
            return const ColoredBox(color: _flood);
          },
        ),
      ),
    ),
  );
}
