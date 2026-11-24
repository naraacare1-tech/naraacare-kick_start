import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/responsive.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Outfit colour of the avatar figure (Figma "Home/Water", "Home/Nutrition",
/// "After sign in"). Assets are built from the Figma exports by
/// `tools/make_avatars.py`; one figure per sex until body-type art arrives
/// (OQ-56).
enum AvatarLook { water, food, neutral, pick }

/// How long the colour takes to rise to a new level.
const Duration avatarFillDuration = Duration(milliseconds: 1200);

/// How long the wave keeps moving after a level change before it settles
/// (the surface wave itself keeps moving; see _waveCycle).
const Duration avatarWaveDuration = Duration(milliseconds: 3000);

/// Strength of the light tint over the whole figure (the "empty" part).
const double _tintOpacity = 0.18;

/// Strength of the filled part (darker, from the feet up).
const double _fillOpacity = 0.42;

/// Fill colour per tracker (owner, 2026-11-07): water sky blue, nutrition
/// green, sleep (the neutral figure) purple.
Color avatarFillColour(AvatarLook look) => switch (look) {
  AvatarLook.water => NcColors.avatarWater,
  AvatarLook.food => NcColors.avatarNutrition,
  AvatarLook.neutral || AvatarLook.pick => NcColors.avatarSleep,
};

/// The full-body avatar for a sex (`female` / `male`; anything else shows
/// the male figure, as the API defaults before onboarding step 1).
///
/// With [fill] (0..1) the figure shows progress: the whole body is lightly
/// tinted in the tracker colour, and a darker fill rises from the feet to
/// the [fill] level with a moving wave on top whenever the level changes (a
/// drink, meal or sleep was logged). The level comes from the server (tank
/// level, avatar fill, sleep score); the app does no health maths.
class NcAvatarFigure extends StatelessWidget {
  const new({
    required this.sex,
    required this.look,
    super.key,
    this.height,
    this.fill,
    this.semanticLabel,
    this.scaleWithScreen = true,
  });

  final String? sex;
  final AvatarLook look;

  /// Height in Figma dp; scaled to the phone (see responsive.dart) unless
  /// [scaleWithScreen] is false (the caller already fitted it to the space).
  final double? height;
  final double? fill;
  final String? semanticLabel;
  final bool scaleWithScreen;

  static String asset(String? sex, AvatarLook look) =>
      'assets/avatars/${sex == 'female' ? 'female' : 'male'}_${look.name}.webp';

  @override
  Widget build(BuildContext context) {
    final base = this.height;
    final height = base != null && scaleWithScreen
        ? context.scaled(base)
        : base;
    final level = fill;
    if (level == null) {
      return Image.asset(
        asset(sex, look),
        height: height,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        errorBuilder: (context, _, _) => _Fallback(height: height),
      );
    }
    return _FillingFigure(
      asset: asset(sex, look),
      colour: avatarFillColour(look),
      level: level.clamp(0, 1).toDouble(),
      height: height,
      semanticLabel: semanticLabel,
    );
  }
}

class _Fallback extends StatelessWidget {
  const new({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.accessibility_new,
    size: (height ?? NcSize.icon * 4) / 2,
    color: context.nc.primary,
  );
}

/// One surface wave length travels across the figure in this time.
const _waveCycle = Duration(milliseconds: 2400);

class _FillingFigure extends StatefulWidget {
  const new({
    required this.asset,
    required this.colour,
    required this.level,
    this.height,
    this.semanticLabel,
  });

  final String asset;
  final Color colour;
  final double level;
  final double? height;
  final String? semanticLabel;

  @override
  State<_FillingFigure> createState() => _FillingFigureState();
}

class _FillingFigureState extends State<_FillingFigure>
    with TickerProviderStateMixin {
  /// The level change: rises to the new level, with a bigger swell.
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: avatarWaveDuration,
  );

  /// The surface wave, always moving (owner 2026-11-08); still only with
  /// the system "remove animations" setting.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: _waveCycle,
  );
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      if (mounted) setState(() => _image = info.image);
    },
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );
  ui.Image? _image;
  bool _failed = false;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    // Starts empty on first show, then rises to the level.
    _rise.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _FillingFigure old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _resolve();
    if (old.level != widget.level) {
      _from = _levelAt(old.level);
      _rise.forward(from: 0);
    }
  }

  void _resolve() {
    final stream = AssetImage(widget.asset)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _rise.dispose();
    _wave.dispose();
    super.dispose();
  }

  /// The level shown now, rising from [_from] to [target] in
  /// [avatarFillDuration] (the first part of the wave animation).
  double _levelAt(double target) {
    final t =
        (_rise.value *
                avatarWaveDuration.inMilliseconds /
                avatarFillDuration.inMilliseconds)
            .clamp(0.0, 1.0);
    return ui.lerpDouble(_from, target, Curves.easeOutCubic.transform(t))!;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (_failed) return _Fallback(height: widget.height);
    if (image == null) return SizedBox(height: widget.height);
    final still = MediaQuery.disableAnimationsOf(context);
    final figure = AspectRatio(
      aspectRatio: image.width / image.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_rise, _wave]),
        builder: (context, _) => CustomPaint(
          painter: _FillPainter(
            image: image,
            colour: widget.colour,
            level: still ? widget.level : _levelAt(widget.level),
            // One wave length travels by per cycle; a level change adds a
            // swell that settles back to the steady wave.
            phase: still ? 0 : _wave.value * 2 * math.pi,
            swell: still ? 0 : 1 - _rise.value,
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: widget.height == null
          ? figure
          : SizedBox(height: widget.height, child: figure),
    );
  }
}

/// Paints the figure, then the tint and the wave fill clipped to the
/// figure's own shape (its alpha), multiplied so folds and shading show.
class _FillPainter extends CustomPainter {
  new({
    required this.image,
    required this.colour,
    required this.level,
    required this.phase,
    required this.swell,
  });

  final ui.Image image;
  final Color colour;
  final double level;
  final double phase;
  final double swell;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas
      ..drawImageRect(
        image,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..saveLayer(dst, Paint()..blendMode = BlendMode.multiply)
      ..drawRect(dst, Paint()..color = colour.withValues(alpha: _tintOpacity));
    if (level > 0) {
      // Flatter near empty and full; a steady 1 % wave, up to 2.5 % while
      // the level changes.
      final edge = math.sin(math.pi * level).clamp(0.4, 1.0);
      final amplitude = size.height * (0.01 + 0.015 * swell) * edge;
      final top = size.height * (1 - level);
      canvas
        ..drawPath(
          _wave(size, top, amplitude, phase + math.pi),
          Paint()..color = colour.withValues(alpha: _fillOpacity * 0.5),
        )
        ..drawPath(
          _wave(size, top, amplitude, phase),
          Paint()..color = colour.withValues(alpha: _fillOpacity),
        );
    }
    canvas
      ..drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.dstIn,
      )
      ..restore();
  }

  Path _wave(Size size, double top, double amplitude, double shift) {
    final path = Path()..moveTo(0, size.height);
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final y = top + amplitude * math.sin(2 * math.pi * i / steps + shift);
      path.lineTo(x, y);
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.image != image ||
      old.colour != colour ||
      old.level != level ||
      old.phase != phase ||
      old.swell != swell;
}

/// A round side action on the avatar (Figma H1: more, share, info).
class NcAvatarAction {
  const new({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;
}

/// One page of the Home avatar carousel (Figma H1): the figure centred
/// with the metric card over its top-left corner and the round actions down
/// the right side (more, share, info). Its height comes from
/// [NcAvatarStageHeight] when a parent provides one (Home fills the space
/// down to the pager), else [height].
///
/// With [onShare] a Share action is added after the first action. Sharing
/// stays inside NaraaCare (circles and connections, owner 2026-11-08); the
/// caller opens that sheet.
class NcAvatarStage extends StatefulWidget {
  const new({
    required this.sex,
    required this.look,
    required this.card,
    super.key,
    this.fill,
    this.actions = const [],
    this.onShare,
    this.sideBadge,
  });

  static const double height = 440;

  final String? sex;
  final AvatarLook look;
  final Widget card;
  final double? fill;
  final List<NcAvatarAction> actions;
  final VoidCallback? onShare;

  /// Shown on the right beside the legs, where the figure is narrow (Home:
  /// the "water added / meal saved / sleep saved" badge, owner 2026-11-24).
  final Widget? sideBadge;

  /// Width / height of the figure art (assets/avatars, OQ-56).
  static double aspect(String? sex) =>
      sex == 'female' ? 291 / 1031 : 409 / 1061;

  @override
  State<NcAvatarStage> createState() => _NcAvatarStageState();
}

class _NcAvatarStageState extends State<NcAvatarStage> {
  /// How far the card may reach over the figure's background margin.
  static const double _cardOverlap = 24;
  static const double _cardMinWidth = 132;

  /// The side badge starts this far down the stage (thigh level, below the
  /// hands) and may reach this far into the figure box (the legs leave the
  /// outer part of it empty).
  static const double _badgeTop = 0.56;
  static const double _badgeInset = 0.22;
  static const double _badgeMinWidth = 88;
  static const double _badgeMaxWidth = 140;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final height = NcAvatarStageHeight.of(context) ?? NcAvatarStage.height;
    Widget button(
      IconData icon,
      String tooltip,
      Color? colour,
      void Function(BuildContext button) onPressed,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.cardGap),
      child: Material(
        color: nc.surface,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: nc.textSecondary.withValues(alpha: 0.3),
        child: Builder(
          builder: (context) => IconButton(
            tooltip: tooltip,
            icon: Icon(icon, color: colour ?? nc.textPrimary),
            onPressed: () => onPressed(context),
          ),
        ),
      ),
    );
    final buttons = [
      for (final a in widget.actions)
        button(a.icon, a.tooltip, a.color, (_) => a.onPressed()),
    ];
    final onShare = widget.onShare;
    if (onShare != null) {
      buttons.insert(
        buttons.isEmpty ? 0 : 1,
        button(
          Icons.share_outlined,
          MaterialLocalizations.of(context).shareButtonLabel,
          null,
          (_) => onShare(),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          // Figma H1: the card sits beside the face, never over it. On a
          // narrow screen the card takes the free space on the left (its text
          // wraps) and the figure moves right to make room.
          final width = box.maxWidth;
          final figureWidth = height * NcAvatarStage.aspect(widget.sex);
          final free = (width - figureWidth) / 2;
          final cardWidth = (free + _cardOverlap).clamp(
            _cardMinWidth,
            width * 0.45,
          );
          final shift = (cardWidth - _cardOverlap - free).clamp(
            0.0,
            free.clamp(0.0, double.infinity),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: ColoredBox(
                    color: nc.surface,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: free + shift,
                          width: figureWidth,
                          child: NcAvatarFigure(
                            sex: widget.sex,
                            look: widget.look,
                            height: height,
                            fill: widget.fill,
                            scaleWithScreen: false,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: NcSpace.cardGap,
                          width: cardWidth,
                          child: widget.card,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: NcSpace.cardGap,
                child: Column(children: buttons),
              ),
              if (widget.sideBadge case final badge?)
                Positioned(
                  right: 0,
                  top: height * _badgeTop,
                  width:
                      (width - (free + shift + figureWidth * (1 - _badgeInset)))
                          .clamp(_badgeMinWidth, _badgeMaxWidth),
                  child: badge,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Lets a page size the avatar stages below it to the space it has.
class NcAvatarStageHeight extends InheritedWidget {
  const new({required this.height, required super.child, super.key});

  final double height;

  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NcAvatarStageHeight>()?.height;

  @override
  bool updateShouldNotify(NcAvatarStageHeight oldWidget) =>
      oldWidget.height != height;
}
