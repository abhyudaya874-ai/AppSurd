import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';


/// Orb states drive distinct motion/color behavior:
/// idle breathe → listening (level-reactive) → thinking (swirl) →
/// speaking (rhythmic pulse) → error shiver.
enum OrbState { idle, listening, thinking, speaking, error }

/// The Siri-style orb. 3–5 radial-gradient blobs on offset Lissajous paths,
/// sine "noise" on radii, composited with `plus` blending over one blurred
/// glow layer. ONE [AnimationController] drives time; mic level smooths in.
///
/// Wrapped in [RepaintBoundary] by the caller for cheap re-rasterization.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.state,
    required this.tint,
    this.level = 0, // smoothed mic level 0..1
    this.size = 180,
  });

  final OrbState state;
  final Color tint;
  final double level;
  final double size;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..repeat();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Exponential smoothing — level never jitters.
    _level = ui.lerpDouble(_level, widget.level, 0.25)!;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) => CustomPaint(
            painter: _OrbPainter(
              t: _t.value * 60, // seconds-ish sweep
              state: widget.state,
              tint: widget.tint,
              level: reduced ? 0.3 : _level,
              frozen: reduced,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.state,
    required this.tint,
    required this.level,
    required this.frozen,
  });

  final double t; // ~seconds since start
  final OrbState state;
  final Color tint;
  final double level;
  final bool frozen;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final baseR = size.width * 0.30;
    final tt = frozen ? 0.0 : t;

    // ---- State-driven parameters ----
    double breathe = 1 + 0.03 * sin(tt * 1.6); // idle ±3%
    double distort = 0.18;
    double swirl = 0.0;
    double brightness = 0.85;
    double errorOffset = 0;
    switch (state) {
      case OrbState.idle:
        break;
      case OrbState.listening:
        distort = 0.22 + level * 0.55;
        breathe = 1 + level * 0.25 + 0.02 * sin(tt * 7);
        brightness = 0.85 + level * 0.5;
      case OrbState.thinking:
        swirl = tt * 2.4;
        distort = 0.26;
        breathe = 1 + 0.05 * sin(tt * 5);
      case OrbState.speaking:
        // Rhythmic pulse — a synthetic envelope since TTS has no amplitude.
        final env = (0.5 + 0.5 * sin(tt * 9)) * (0.6 + 0.4 * sin(tt * 2.3));
        breathe = 1 + env * 0.18;
        distort = 0.2 + env * 0.25;
        brightness = 0.9 + env * 0.3;
      case OrbState.error:
        errorOffset = sin(tt * 40) * 4 * exp(-(tt % 1) * 4);
    }

    final colors = _palette(tint);

    // ---- Blurred glow layer (the only blur in the frame) ----
    canvas.drawCircle(
      c + Offset(errorOffset, 0),
      baseR * breathe * 1.25,
      Paint()
        ..color = colors[0].withValues(alpha: 0.35 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    // ---- Blobs: overlapping gradient discs on Lissajous paths ----
    canvas.saveLayer(
        Offset.zero & size, Paint()..blendMode = BlendMode.plus);
    for (var i = 0; i < 4; i++) {
      final ph = tt * (0.5 + i * 0.17) + swirl * (1 + i * 0.3) + i * 1.9;
      final wob = sin(tt * (1.1 + i * 0.4) + i * 2.6);
      final cx = c.dx +
          errorOffset +
          baseR * 0.28 * sin(ph * 1.3) +
          baseR * distort * 0.15 * sin(tt * 3 + i);
      final cy = c.dy +
          baseR * 0.28 * cos(ph * 1.7) +
          baseR * distort * 0.15 * cos(tt * 2.4 + i * 1.3);
      final r = baseR *
          breathe *
          (0.62 + 0.2 * wob + distort * level * 0.3 * (i.isEven ? 1 : -1));
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            r,
            [
              colors[i % colors.length]
                  .withValues(alpha: 0.75 * brightness),
              colors[i % colors.length].withValues(alpha: 0.0),
            ],
          ),
      );
    }
    canvas.restore();

    // ---- Core: hot center disc ----
    canvas.drawCircle(
      c + Offset(errorOffset, 0),
      baseR * breathe * 0.34,
      Paint()
        ..color = Colors.white
            .withValues(alpha: state == OrbState.error ? 0.9 : 0.85 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  List<Color> _palette(Color tint) => switch (state) {
        OrbState.error => const [
            Color(0xFFFF5A5A),
            Color(0xFFFF8A5C),
            Color(0xFFD63A3A),
            Color(0xFFFFB199),
          ],
        OrbState.speaking => [
            tint,
            HSLColor.fromColor(tint)
                .withLightness(0.7)
                .withHue(
                    (HSLColor.fromColor(tint).hue + 30) % 360)
                .toColor(),
            const Color(0xFFFFC88A), // warmer accent while speaking
            tint.withValues(alpha: 0.9),
          ],
        _ => [
            tint,
            HSLColor.fromColor(tint)
                .withHue((HSLColor.fromColor(tint).hue + 40) % 360)
                .toColor(),
            HSLColor.fromColor(tint)
                .withHue((HSLColor.fromColor(tint).hue - 30) % 360)
                .withSaturation(0.8)
                .toColor(),
            Colors.white.withValues(alpha: 0.8),
          ],
      };

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.state != state ||
      old.level != level ||
      old.tint != tint;
}
