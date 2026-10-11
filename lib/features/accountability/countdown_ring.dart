import 'package:flutter/material.dart';

/// Smooth circular countdown — continuous sweep (not per-second jumps), color
/// lerping from the accent to error in the last 10 seconds.
class CountdownRing extends StatefulWidget {
  const CountdownRing({
    super.key,
    required this.totalSeconds,
    required this.onFinished,
    this.size = 180,
  });

  final int totalSeconds;
  final VoidCallback onFinished;
  final double size;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: Duration(seconds: widget.totalSeconds),
        )..addStatusListener((s) {
          if (s == AnimationStatus.dismissed) widget.onFinished();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Run 1→0 so value = fraction remaining.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
      widget.onFinished();
    } else {
      _controller.reverse(from: 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final remaining = _controller.value * widget.totalSeconds;
        final urgent = remaining <= 10;
        final color = Color.lerp(
          theme.colorScheme.primary,
          theme.colorScheme.error,
          urgent ? (1 - remaining / 10) : 0,
        );
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _RingPainter(
            progress: _controller.value,
            color: color!,
            track: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          child: SizedBox.square(
            dimension: widget.size,
            child: Center(
              child: Text(
                '${remaining.ceil()}',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: color,
                  fontFeatures: const [],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -3.14159 / 2,
      2 * 3.14159 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
