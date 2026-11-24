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
      _progress = const AlwaysStoppedAnimation(1); // the last frame
      _played.complete();
    }
    unawaited(widget.onStart());
    unawaited(_played.future.then((_) => widget.onFinished()));
  }

  /// On a cold start (first launch above all) the database, secure storage
  /// and fonts load while the first frames draw, so frames were dropped and
  /// the animation jumped ahead: the user saw only its end (owner
  /// 2026-11-24). Start only after the first frame is on screen plus a short
  /// settle time, so the whole animation plays.
  static const _settle = Duration(milliseconds: 400);

  /// The final frame (logo and "Naraa Care") stays this long (owner
  /// 2026-11-24: "increase splash screen time"); about 4.4 s in all.
  static const _hold = Duration(milliseconds: 1500);

  /// What the Lottie shows: frame 0 during the settle time, the animation,
  /// then the last frame during the hold. One controller drives all three
  /// (no timers), so tests and the "remove animations" setting behave.
  Animation<double> _progress = const AlwaysStoppedAnimation(0);

  void _loaded(LottieComposition composition) {
    if (_played.isCompleted) return;
    final total = _settle + composition.duration + _hold;
    final start = _settle.inMicroseconds / total.inMicroseconds;
    final end =
        (_settle + composition.duration).inMicroseconds / total.inMicroseconds;
    _anim.duration = total;
    setState(
      () => _progress = CurvedAnimation(
        parent: _anim,
        curve: Interval(start, end),
      ),
    );
    // Start once the first frame is on screen, not while the app is still
    // loading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _played.isCompleted) return;
      unawaited(
        _anim.forward().whenComplete(() {
          if (!_played.isCompleted) _played.complete();
        }),
      );
    });
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
          controller: _progress,
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
