import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/transitions.dart';
import '../shell/app_shell.dart';

/// Launch sequence: the receipt logo mark draws itself (outline, then a
/// checkmark via path metrics), the wordmark fades in, then we fade-through
/// to the task list. One controller drives the whole choreography.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.hero * 3,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context)
            .pushReplacement(AppTransitions.fadeThrough(const AppShell()));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion must be read here — MediaQuery isn't available in
    // initState.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
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
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  size: const Size(96, 110),
                  painter: _ReceiptLogoPainter(
                    progress: _controller.value,
                    ink: theme.colorScheme.primary,
                    paper: theme.colorScheme.surfaceContainerHighest,
                    check: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _controller,
                curve: const Interval(0.6, 1, curve: Curves.easeOut),
              ),
              child: Text('Receipts', style: theme.textTheme.displayMedium),
            ),
            const SizedBox(height: AppSpacing.xs),
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _controller,
                curve: const Interval(0.7, 1, curve: Curves.easeOut),
              ),
              child: Text(
                'prove it or it didn\'t happen',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the receipt-paper outline (with zigzag tear bottom), then a
/// checkmark — both revealed progressively by animating path metrics.
class _ReceiptLogoPainter extends CustomPainter {
  const _ReceiptLogoPainter({
    required this.progress,
    required this.ink,
    required this.paper,
    required this.check,
  });

  final double progress;
  final Color ink;
  final Color paper;
  final Color check;

  /// Receipt silhouette: rounded top, straight sides, zigzag torn bottom.
  Path _outline(Size size) {
    final w = size.width;
    final h = size.height;
    const r = 14.0;
    const teeth = 4;
    final zigY = h - 12;
    final path = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, zigY);
    for (var i = 0; i < teeth; i++) {
      final x1 = w - (w / teeth) * (i + 0.5);
      final x2 = w - (w / teeth) * (i + 1);
      path
        ..lineTo(x1, h)
        ..lineTo(x2, zigY);
    }
    return path
      ..lineTo(0, r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Fill the paper first (fades in with the first 20% of progress).
    final fillT = (progress / 0.2).clamp(0.0, 1.0);
    canvas.drawPath(
      _outline(size),
      Paint()..color = paper.withValues(alpha: fillT),
    );

    // Stroke the outline over 0→60% of progress.
    final outlineT = (progress / 0.6).clamp(0.0, 1.0);
    final outlinePaint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in _outline(size).computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * outlineT),
        outlinePaint,
      );
    }

    // Checkmark draws in over the last 40%.
    final checkT = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
    if (checkT > 0) {
      final checkPath = Path()
        ..moveTo(size.width * 0.26, size.height * 0.45)
        ..lineTo(size.width * 0.44, size.height * 0.62)
        ..lineTo(size.width * 0.76, size.height * 0.26);
      final checkPaint = Paint()
        ..color = check
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final metric in checkPath.computeMetrics()) {
        canvas.drawPath(
          metric.extractPath(0, metric.length * checkT),
          checkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ReceiptLogoPainter old) => old.progress != progress;
}
