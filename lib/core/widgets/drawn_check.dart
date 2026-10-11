import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A checkmark that draws itself in via path metrics — used for completed
/// verification steps and the task-done reveal.
class DrawnCheck extends StatefulWidget {
  const DrawnCheck({
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 2.4,
    this.animate = true,
  });

  final double size;
  final Color? color;
  final double strokeWidth;
  final bool animate;

  @override
  State<DrawnCheck> createState() => _DrawnCheckState();
}

class _DrawnCheckState extends State<DrawnCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CheckPainter(
          t: Curves.easeOut.transform(_controller.value),
          color: color,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(
      {required this.t, required this.color, required this.strokeWidth});
  final double t;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.55)
      ..lineTo(size.width * 0.42, size.height * 0.75)
      ..lineTo(size.width * 0.82, size.height * 0.28);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
