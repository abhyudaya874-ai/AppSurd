// READ THIS FIRST — custom-painted 4-detent slider. Thumb stretches on
// drag, spring-snaps on release, haptic at detent crossing.
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';


import '../../core/theme/motion.dart';

/// The signature strength slider: 4 detents (Swift → Deep), a thumb that
/// stretches horizontally while dragged and snaps to the nearest detent with
/// a spring, haptic ticks per detent crossing, and a gradient fill whose hue
/// runs through the per-tier provider tints.
///
/// Value is a continuous 0..3; the detent index is `value.round()`.
class StrengthSlider extends StatefulWidget {
  const StrengthSlider({
    super.key,
    required this.value,
    required this.detentColors,
    required this.onChanged,
    this.onChangeEnd,
  });

  /// Continuous position 0..3.
  final double value;

  /// One color per detent — feeds the fill gradient + active dot.
  final List<Color> detentColors;

  /// Fires whenever the continuous value crosses into a new detent while
  /// dragging — the pill label live-updates from this.
  final ValueChanged<int> onChanged;

  /// Fires after the snap settles — where selection state is committed.
  final ValueChanged<int>? onChangeEnd;

  @override
  State<StrengthSlider> createState() => _StrengthSliderState();
}

class _StrengthSliderState extends State<StrengthSlider>
    with SingleTickerProviderStateMixin {
  static const _detents = 4;

  late double _value;
  double _stretch = 1; // squash-stretch factor on the thumb
  int _lastDetent = 0;
  late final AnimationController _snap;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(0, _detents - 1.0);
    _lastDetent = _value.round();
    _snap = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _value = _snap.value));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StrengthSlider old) {
    super.didUpdateWidget(old);
    // External change (e.g. custom model cleared) springs the thumb over.
    if (!_dragging && old.value != widget.value) {
      _animateTo(widget.value);
    }
  }

  void _animateTo(double target) {
    _snap.value = _value;
    _snap.animateWith(
      SpringSimulation(AppMotion.spring, _value, target.clamp(0, 3.0), 0),
    );
  }

  void _onDrag(DragUpdateDetails d, double width) {
    final next = (_value + d.primaryDelta! / width * (_detents - 1))
        .clamp(0.0, (_detents - 1).toDouble());
    // Thumb widens with drag speed — the squash; springs back on release.
    final vel = d.primaryDelta!.abs();
    setState(() {
      _value = next;
      _stretch = 1 + (vel * 0.06).clamp(0.0, 0.5);
    });
    final detent = _value.round();
    if (detent != _lastDetent) {
      _lastDetent = detent;
      HapticFeedback.selectionClick();
      widget.onChanged(detent);
    }
  }

  void _onDragEnd(double width) {
    setState(() => _dragging = false);
    final target = _value.round().toDouble();
    _animateTo(target);
    // Stretch eases back with a slight lag behind the snap.
    Future.delayed(AppMotion.fast, () {
      if (mounted) setState(() => _stretch = 1);
    });
    widget.onChangeEnd?.call(target.toInt());
  }

  void _onTap(TapUpDetails d, double width) {
    final t = (d.localPosition.dx / width * (_detents - 1)).clamp(0.0, 3.0);
    final detent = t.round();
    if (detent != _lastDetent) {
      _lastDetent = detent;
      HapticFeedback.selectionClick();
      widget.onChanged(detent);
    }
    _animateTo(detent.toDouble());
    widget.onChangeEnd?.call(detent);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 28; // thumb half-width padding
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (d) => _onDrag(d, width),
          onHorizontalDragEnd: (_) => _onDragEnd(width),
          onTapUp: (d) => _onTap(d, width),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: CustomPaint(
                size: Size(width, 44),
                painter: _SliderPainter(
                  value: _value,
                  detents: _detents,
                  stretch: _stretch,
                  colors: widget.detentColors,
                  trackColor: Theme.of(context).colorScheme.outline,
                  thumbColor: Theme.of(context).colorScheme.surface,
                  dragging: _dragging,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints track, gradient fill, detent dots, and the stretching thumb.
class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.value,
    required this.detents,
    required this.stretch,
    required this.colors,
    required this.trackColor,
    required this.thumbColor,
    required this.dragging,
  });

  final double value;
  final int detents;
  final double stretch;
  final List<Color> colors;
  final Color trackColor;
  final Color thumbColor;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final usableW = size.width;
    double xAt(double v) => v / (detents - 1) * usableW;
    final thumbX = xAt(value);

    // Track
    final trackRect = Rect.fromCenter(
      center: Offset(usableW / 2, cy),
      width: usableW,
      height: 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(2)),
      Paint()..color = trackColor.withValues(alpha: 0.4),
    );

    // Filled portion: horizontal gradient across detent colors, ending at the
    // live thumb position so the hue visibly shifts as you drag.
    if (thumbX > 0) {
      final gradient = LinearGradient(
        colors: [
          for (var i = 0; i < detents; i++) colors[i % colors.length],
        ],
      );
      final fillRect = Rect.fromLTWH(0, cy - 2, thumbX, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
        Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, usableW, 4)),
      );
    }

    // Detent dots — filled when passed, hollow when ahead.
    for (var i = 0; i < detents; i++) {
      final dx = xAt(i.toDouble());
      final active = i <= value;
      final color = colors[i % colors.length];
      canvas.drawCircle(
        Offset(dx, cy),
        4,
        Paint()
          ..color = active ? color : trackColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill,
      );
      if (!active) {
        canvas.drawCircle(
          Offset(dx, cy),
          4,
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }

    // Thumb — stretches horizontally (squash) while dragging.
    final tw = 26 * stretch;
    final th = 20 / (stretch * 0.6 + 0.4);
    final thumbRect = Rect.fromCenter(
      center: Offset(thumbX, cy),
      width: tw,
      height: th,
    );
    final thumbRRect =
        RRect.fromRectAndRadius(thumbRect, Radius.circular(th / 2));
    canvas.drawRRect(
      thumbRRect.shift(const Offset(0, 1.5)),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(thumbRRect, Paint()..color = thumbColor);
    canvas.drawRRect(
      thumbRRect,
      Paint()
        ..color = colors[value.round() % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Tiny grip dot so the thumb reads as draggable.
    canvas.drawCircle(
      Offset(thumbX, cy),
      3.5,
      Paint()..color = colors[value.round() % colors.length],
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.value != value || old.stretch != stretch || old.dragging != dragging;
}
