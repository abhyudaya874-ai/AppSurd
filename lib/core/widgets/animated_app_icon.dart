import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Every icon kind the shell uses — custom-painted, animated on `active`.
enum AppIconType {
  tasks,
  ask,
  arena,
  settings,
  add,
  orb,
  trash,
  filter,
  verified,
  chevron,
  shield,
  receipt,
}

/// A custom-painted vector icon with stroke-draw animations. One
/// [AnimationController] per icon; [active] drives it forward/reverse and a
/// tap adds a 0.9→1 spring scale. All painters respect reduced motion (jump
/// to end state). Replaces every stock Material icon in the shell.
class AnimatedAppIcon extends StatefulWidget {
  const AnimatedAppIcon({
    super.key,
    required this.type,
    this.active = false,
    this.size = 24,
    this.color,
    this.onTap,
  });

  final AppIconType type;

  /// True = animated/"on" state (e.g. selected tab). Toggles animate.
  final bool active;
  final double size;
  final Color? color;
  final VoidCallback? onTap;

  @override
  State<AnimatedAppIcon> createState() => _AnimatedAppIconState();
}

class _AnimatedAppIconState extends State<AnimatedAppIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _press = 1;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: AppMotion.base)
      ..value = widget.active ? 1 : 0;
  }

  @override
  void didUpdateWidget(AnimatedAppIcon old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      widget.active ? _c.forward() : _c.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && widget.active) {
      _c.value = 1; // reduced motion: settle instantly
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    final icon = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _IconPainter(
              type: widget.type,
              t: Curves.easeOutCubic.transform(_c.value),
              color: color,
              active: widget.active,
            ),
          ),
        ),
      ),
    );
    if (widget.onTap == null) return icon;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _press = 0.9),
      onTapUp: (_) => setState(() => _press = 1),
      onTapCancel: () => setState(() => _press = 1),
      child: AnimatedScale(
        scale: _press,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: icon,
      ),
    );
  }
}

/// One painter for all icons — each draws strokes scaled by [t] so the icon
/// "writes itself" in when activated. Canvas is a 24-unit logical square.
class _IconPainter extends CustomPainter {
  const _IconPainter({
    required this.type,
    required this.t,
    required this.color,
    required this.active,
  });

  final AppIconType type;
  final double t; // 0..1 activation
  final Color color;
  final bool active;

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  /// Draws [path] partially — fraction of its length = [frac] — the classic
  /// draw-on effect via PathMetrics.
  void _drawOn(Canvas canvas, Path path, double frac, {Paint? paint}) {
    final p = paint ?? _stroke;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * frac.clamp(0.0, 1.0)), p);
    }
  }

  /// Helper: frac for sub-animation i of n (staggered).
  double _seg(int i, int n, {double lead = 0.15}) {
    final start = i * (1 - lead) / n;
    final end = start + (1 + lead) / n;
    return ((t - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // logical 24x24 box
    canvas.save();
    canvas.scale(s);
    switch (type) {
      case AppIconType.tasks:
        for (var i = 0; i < 3; i++) {
          final y = 6.0 + i * 6;
          final row = Path()
            ..moveTo(6, y)
            ..lineTo(19, y);
          _drawOn(canvas, row, _seg(i, 3));
          canvas.drawCircle(
            Offset(3.5, y),
            1.1,
            _fill..color = color.withValues(alpha: _seg(i, 3)),
          );
        }
        // Tick on the last row when active.
        if (t > 0.6) {
          final tick = Path()
            ..moveTo(16, 19)
            ..lineTo(18.4, 21.4)
            ..lineTo(22, 17);
          _drawOn(canvas, tick, (t - 0.6) / 0.4, paint: _stroke..color = color);
        }
      case AppIconType.ask:
        final bubble = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(3, 4, 18, 13),
              const Radius.circular(5),
            ),
          )
          ..moveTo(8, 17)
          ..lineTo(8, 21)
          ..lineTo(12.5, 17);
        _drawOn(canvas, bubble, t.clamp(0, 1));
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(8.5 + i * 3.5, 10.5),
            1.2,
            _fill..color = color.withValues(alpha: _seg(i, 3, lead: 0.3)),
          );
        }
      case AppIconType.arena:
        // Two rings that slide apart when active (versus feel).
        final dx = t * 2.2;
        canvas.drawCircle(Offset(9 + dx, 12), 5.2, _stroke);
        canvas.drawCircle(Offset(15 - dx, 12), 5.2, _stroke);
      case AppIconType.settings:
        // Gear: 8 teeth + center circle; rotates 90° on activate.
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(t * pi / 2);
        canvas.translate(-12, -12);
        canvas.drawCircle(const Offset(12, 12), 3.2, _stroke);
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4;
          final p = Path()
            ..moveTo(12 + cos(a) * 5.4, 12 + sin(a) * 5.4)
            ..lineTo(12 + cos(a) * 8.2, 12 + sin(a) * 8.2);
          _drawOn(canvas, p, 1);
        }
        canvas.restore();
      case AppIconType.add:
        // Plus that rotates into × while open.
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(t * pi / 4);
        canvas.translate(-12, -12);
        _drawOn(
          canvas,
          Path()
            ..moveTo(12, 5)
            ..lineTo(12, 19),
          1,
        );
        _drawOn(
          canvas,
          Path()
            ..moveTo(5, 12)
            ..lineTo(19, 12),
          1,
        );
        canvas.restore();
      case AppIconType.orb:
        // Mic capsule + expanding sound arcs.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(9, 4, 6, 10),
            const Radius.circular(3),
          ),
          _stroke,
        );
        _drawOn(
          canvas,
          Path()
            ..moveTo(6.5, 12)
            ..arcToPoint(
              const Offset(17.5, 12),
              radius: const Radius.circular(6),
            ),
          1,
        );
        _drawOn(
          canvas,
          Path()
            ..moveTo(12, 18)
            ..lineTo(12, 21),
          1,
        );
        for (var i = 0; i < 2; i++) {
          final r = 9 + i * 3 + t * 2;
          final f = (t * (i + 1) / 2).clamp(0.0, 0.8);
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(12, 12), radius: r),
            -pi * 0.3,
            -pi * 0.4,
            false,
            _stroke..color = color.withValues(alpha: f),
          );
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(12, 12), radius: r),
            pi * 0.8,
            pi * 0.4,
            false,
            _stroke..color = color.withValues(alpha: f),
          );
        }
      case AppIconType.trash:
        final wob = sin(t * pi) * 0.15;
        canvas.save();
        canvas.translate(12, 5);
        canvas.rotate(-wob * 4);
        canvas.translate(-12, -5);
        _drawOn(
          canvas,
          Path()
            ..moveTo(8 - t * 2, 5 - t * 1.5)
            ..lineTo(16 + t * 2, 5 - t * 1.5),
          1,
        ); // lid lifts
        _drawOn(
          canvas,
          Path()
            ..moveTo(10.5, 4)
            ..lineTo(13.5, 4),
          1,
        );
        canvas.restore();
        final body = Path()
          ..moveTo(6, 7)
          ..lineTo(7, 21)
          ..lineTo(17, 21)
          ..lineTo(18, 7)
          ..close();
        _drawOn(canvas, body, 1);
        _drawOn(
          canvas,
          Path()
            ..moveTo(10, 10)
            ..lineTo(10, 18),
          1,
        );
        _drawOn(
          canvas,
          Path()
            ..moveTo(14, 10)
            ..lineTo(14, 18),
          1,
        );
      case AppIconType.filter:
        for (var i = 0; i < 3; i++) {
          final y = 6.0 + i * 6;
          _drawOn(
            canvas,
            Path()
              ..moveTo(4, y)
              ..lineTo(20, y),
            1,
          );
          // Knobs slide to new positions when active.
          final kx = lerpDouble2(7 + i * 4, 16 - i * 4, t);
          canvas.drawCircle(Offset(kx, y), 2.2, _fill);
        }
      case AppIconType.verified:
        final ring = Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 8.5));
        _drawOn(canvas, ring, (t * 1.6).clamp(0, 1));
        final tick = Path()
          ..moveTo(8, 12.5)
          ..lineTo(11, 15.5)
          ..lineTo(16.5, 9);
        _drawOn(canvas, tick, ((t - 0.5) * 2).clamp(0, 1));
      case AppIconType.chevron:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(t * pi);
        canvas.translate(-12, -12);
        _drawOn(
          canvas,
          Path()
            ..moveTo(7, 10)
            ..lineTo(12, 15)
            ..lineTo(17, 10),
          1,
        );
        canvas.restore();
      case AppIconType.shield:
        final shield = Path()
          ..moveTo(12, 3)
          ..lineTo(20, 6)
          ..quadraticBezierTo(20, 15, 12, 21)
          ..quadraticBezierTo(4, 15, 4, 6)
          ..close();
        _drawOn(canvas, shield, 1);
        final tick = Path()
          ..moveTo(8.5, 11.5)
          ..lineTo(11.2, 14.2)
          ..lineTo(16, 8.8);
        _drawOn(canvas, tick, t);
      case AppIconType.receipt:
        // Paper that unrolls + lines draw on (empty-state loop).
        final unroll = Curves.easeOutCubic.transform(t);
        final body = Path()
          ..moveTo(6, 5)
          ..lineTo(18, 5)
          ..lineTo(18, 5 + 15 * unroll)
          ..lineTo(6, 5 + 15 * unroll)
          ..close();
        _drawOn(canvas, body, 1);
        for (var i = 0; i < 3; i++) {
          final y = 9.0 + i * 4;
          if (5 + 15 * unroll > y) {
            _drawOn(
              canvas,
              Path()
                ..moveTo(8.5, y)
                ..lineTo(8.5 + 7 * _seg(i, 3), y),
              _seg(i, 3),
            );
          }
        }
    }
    canvas.restore();
  }

  static double lerpDouble2(double a, double b, double t) =>
      ui.lerpDouble(a, b, t) ?? a;

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.t != t || old.color != color || old.active != active;
}
