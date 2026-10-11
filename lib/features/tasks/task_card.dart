import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../../core/widgets/pressable.dart';
import 'task_model.dart';

/// One task row in the new shell: animated status ring on the left (open =
/// thin ring, verifying = spinning arc, locked = amber + lock, verified =
/// filled teal + drawn tick), title, meta line, chevron. Hero tag preserved.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    this.accountabilityPending = false,
    this.groupName,
  });

  final Task task;
  final VoidCallback onTap;

  /// Shows the "unresolved accountability" dot when another task is locked.
  final bool accountabilityPending;

  /// Resolved group name for the meta line.
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (task.status) {
      TaskStatus.open => ('needs proof', theme.colorScheme.onSurfaceVariant),
      TaskStatus.verifying => ('verifying', theme.colorScheme.primary),
      TaskStatus.locked =>
        ('challenge pending', theme.colorScheme.tertiary),
      TaskStatus.done => ('verified', theme.colorScheme.primary),
    };
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
        child: Row(children: [
          _StatusRing(status: task.status, color: color),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Hero(
                      tag: 'task-title-${task.id}',
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(
                          task.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  if (task.isDemo)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('demo',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.tertiary)),
                    ),
                  if (accountabilityPending)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message:
                            'Unresolved accountability on another task',
                        child: Icon(Icons.flag_outlined,
                            size: 14,
                            color: theme.colorScheme.tertiary),
                      ),
                    ),
                ]),
                const SizedBox(height: 2),
                // Meta line: group · attempts · status
                Text(
                  '${groupName != null ? '$groupName · ' : ''}'
                  '${task.attempts.length} attempt'
                  '${task.attempts.length == 1 ? '' : 's'} · $label',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Transform.rotate(
            angle: -1.5708, // down-chevron → right-pointing ›
            child: AnimatedAppIcon(
                type: AppIconType.chevron,
                active: false,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

/// The status ring — open: thin ring; verifying: spinning arc; locked:
/// amber ring with a lock glyph; done: filled teal with a drawn tick.
class _StatusRing extends StatefulWidget {
  const _StatusRing({required this.status, required this.color});
  final TaskStatus status;
  final Color color;

  @override
  State<_StatusRing> createState() => _StatusRingState();
}

class _StatusRingState extends State<_StatusRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.status == TaskStatus.verifying) _spin.repeat();
  }

  @override
  void didUpdateWidget(_StatusRing old) {
    super.didUpdateWidget(old);
    if (widget.status == TaskStatus.verifying) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 26,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            status: widget.status,
            color: widget.color,
            spin: _spin.value * 2 * math.pi,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
      {required this.status, required this.color, required this.spin});
  final TaskStatus status;
  final Color color;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 10.5;
    switch (status) {
      case TaskStatus.verifying:
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          spin,
          math.pi * 1.2,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      case TaskStatus.done:
        canvas.drawCircle(c, r, Paint()..color = color);
        final tick = Path()
          ..moveTo(c.dx - 4.5, c.dy + 0.5)
          ..lineTo(c.dx - 1, c.dy + 4)
          ..lineTo(c.dx + 5, c.dy - 4);
        canvas.drawPath(
          tick,
          Paint()
            ..color = const Color(0xFF0B0D10)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      case TaskStatus.locked:
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2);
        // Tiny lock glyph.
        final lock = Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(c.dx, c.dy + 1.5), width: 9, height: 7),
              const Radius.circular(1.5)))
          ..moveTo(c.dx - 3, c.dy - 1.5)
          ..arcToPoint(Offset(c.dx + 3, c.dy - 1.5),
              radius: const Radius.circular(3));
        canvas.drawPath(
            lock,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round);
      case TaskStatus.open:
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.status != status || old.color != color || old.spin != spin;
}
