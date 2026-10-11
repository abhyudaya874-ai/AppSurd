import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';

/// A verified count for one calendar day.
typedef DayContribution = ({DateTime day, int count});

/// GitHub-style 53×7 contribution grid. One [CustomPainter] draws every
/// cell + month labels; a single [AnimationController] drives a diagonal
/// stagger (cells appear left→right top→bottom). Tapping a cell reports the
/// day so the parent can show details — cheap hit-testing, no 371 widgets.
class ContributionHeatmap extends StatefulWidget {
  const ContributionHeatmap({
    super.key,
    required this.contributions,
    required this.onTapDay,
  });

  /// day → count. Missing days render as level 0.
  final Map<DateTime, int> contributions;
  final void Function(DateTime day, int count) onTapDay;

  @override
  State<ContributionHeatmap> createState() => _ContributionHeatmapState();
}

class _ContributionHeatmapState extends State<ContributionHeatmap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final _scroll = ScrollController();

  static const _cell = 12.0, _gap = 3.0, _labelH = 16.0;
  static const _weeks = 53;

  double get _gridW => _weeks * (_cell + _gap);
  double get _gridH => 7 * (_cell + _gap) + _labelH;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: AppMotion.slow)
      ..forward();
    // Ends scrolled at today (rightmost week).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Column/row → the calendar day (columns end at the current week, Monday
  /// is row 0).
  DateTime _dayFor(int week, int weekdayRow, DateTime today) {
    final todayWeekday = today.weekday; // 1=Mon
    final endOfGrid = today.add(
      Duration(days: 7 - todayWeekday),
    ); // Sunday of current week
    return DateTime(
      endOfGrid.year,
      endOfGrid.month,
      endOfGrid.day,
    ).subtract(Duration(days: (_weeks - 1 - week) * 7 + (6 - weekdayRow)));
  }

  int _level(int count) => count <= 0
      ? 0
      : count == 1
      ? 1
      : count <= 3
      ? 2
      : count <= 6
      ? 3
      : 4;

  void _onTap(TapUpDetails d) {
    final col = (d.localPosition.dx / (_cell + _gap)).floor();
    final row = ((d.localPosition.dy - _labelH) / (_cell + _gap)).floor();
    if (col < 0 || col >= _weeks || row < 0 || row >= 7) return;
    final day = _dayFor(col, row, DateTime.now());
    if (day.isAfter(DateTime.now())) return; // future cells are padding
    widget.onTapDay(day, widget.contributions[_key(day)] ?? 0);
  }

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final ramp = [
      theme.colorScheme.surfaceContainerHighest,
      accent.withValues(alpha: 0.25),
      accent.withValues(alpha: 0.45),
      accent.withValues(alpha: 0.7),
      accent,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _gridH,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: RepaintBoundary(
              child: GestureDetector(
                onTapUp: _onTap,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) => CustomPaint(
                    size: Size(_gridW, _gridH),
                    painter: _HeatmapPainter(
                      contributions: widget.contributions,
                      ramp: ramp,
                      labelStyle:
                          theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 9,
                          ) ??
                          const TextStyle(fontSize: 9),
                      progress: MediaQuery.disableAnimationsOf(context)
                          ? 1.0
                          : _anim.value,
                      today: DateTime.now(),
                      dayFor: _dayFor,
                      levelFor: _level,
                      cell: _cell,
                      gap: _gap,
                      labelH: _labelH,
                      weeks: _weeks,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Less → More legend.
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Less',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            for (final c in ramp)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              'More',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Draws the grid: rounded cells per level, month labels at each month's
/// first column, and a diagonal-stagger reveal via [progress].
class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.contributions,
    required this.ramp,
    required this.labelStyle,
    required this.progress,
    required this.today,
    required this.dayFor,
    required this.levelFor,
    required this.cell,
    required this.gap,
    required this.labelH,
    required this.weeks,
  });

  final Map<DateTime, int> contributions;
  final List<Color> ramp;
  final TextStyle labelStyle;
  final double progress;
  final DateTime today;
  final DateTime Function(int week, int row, DateTime today) dayFor;
  final int Function(int count) levelFor;
  final double cell, gap, labelH;
  final int weeks;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    var lastMonth = -1;
    for (var w = 0; w < weeks; w++) {
      for (var r = 0; r < 7; r++) {
        final day = dayFor(w, r, today);
        if (day.isAfter(today)) continue; // future padding cells: skip
        final key = DateTime(day.year, day.month, day.day);
        final count = contributions[key] ?? 0;
        // Diagonal stagger: cells flip on when progress passes their
        // (week + row) share of the grid.
        final order = (w + r) / (weeks + 6);
        if (order > progress) continue;
        paint.color = ramp[levelFor(count)];
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              w * (cell + gap),
              labelH + r * (cell + gap),
              cell,
              cell,
            ),
            const Radius.circular(2.5),
          ),
          paint,
        );
      }
      // Month label at the column where the month flips.
      final first = dayFor(w, 0, today);
      if (first.month != lastMonth && !first.isAfter(today)) {
        lastMonth = first.month;
        final tp = TextPainter(
          text: TextSpan(text: _months[first.month - 1], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(w * (cell + gap), 0));
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.progress != progress || old.contributions != contributions;
}
