import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';
import '../tasks/group_model.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import 'auto_schedule.dart';
import 'block_layout.dart';
import 'working_hours.dart';
import 'working_hours_editor.dart';

/// How many days are visible side-by-side and how far the strip reaches.
const _visibleDays = 5;
const _dayRange = 60; // ±60 days around today
const _hourH = 56.0; // vertical pixels per hour
const _gutterW = 46.0; // time gutter width

/// Position preview while a block is being dragged (which column, top in
/// minutes-of-day).
typedef DragPreview = ({String taskId, int dayIndex, int topMin});
typedef ResizePreview = ({String taskId, int durMin});

/// Schedule tab — a Google-Calendar-like week strip: 5 day columns over a
/// shared 24h vertical scroll, red now-line, draggable task blocks
/// (15-minute snap, cross-day moves, bottom-handle resize), an unscheduled
/// tray whose chips drop onto the grid, and quick-create on long-press.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late final PageController _days;
  final _v = ScrollController();
  final _gridKey = GlobalKey(); // the PageView area, for drop math

  /// Live previews — kept in notifiers so only blocks/ghosts rebuild, not
  /// the whole screen (per the perf rules).
  final _drag = ValueNotifier<DragPreview?>(null);
  final _resize = ValueNotifier<ResizePreview?>(null);

  Timer? _autoScroll;
  double _grabMin = 0; // where inside the block the finger grabbed
  double _resizeDelta = 0;

  @override
  void initState() {
    super.initState();
    _days = PageController(
        viewportFraction: 1 / _visibleDays, initialPage: _dayRange);
    // Land roughly on "now" so the current hour is visible on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_v.hasClients) return;
      final now = DateTime.now();
      final target = ((now.hour - 1).clamp(0, 23)) * _hourH;
      _v.jumpTo(target.clamp(0.0, _v.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _days.dispose();
    _v.dispose();
    _autoScroll?.cancel();
    super.dispose();
  }

  /// Page index → calendar date (page `_dayRange` is today).
  DateTime _dateFor(int page) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(Duration(days: page - _dayRange));
  }

  Future<void> _autoScheduleAll() async {
    HapticFeedback.mediumImpact();
    final tasks = ref.read(tasksProvider).value ?? const [];
    final hours = ref.read(workingHoursProvider);
    final placements = autoSchedule(tasks: tasks, hours: hours);
    if (placements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Nothing free to schedule — open tasks all placed.')));
      return;
    }
    final n = ref.read(tasksProvider.notifier);
    for (final p in placements) {
      final t = tasks.firstWhere((t) => t.id == p.taskId);
      await n.updateTask(
          t.copyWith(scheduledStart: p.start, durationMin: p.durationMin));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Scheduled ${placements.length} task'
              '${placements.length == 1 ? '' : 's'} into working hours.')));
    }
  }

  /// Commits a tray drop or block move at a 15-minute slot on [dayIndex].
  Future<void> _place(Task task, int dayIndex, int topMin) async {
    final date = _dateFor(dayIndex);
    final snapped = (topMin / 15).round() * 15;
    final start = DateTime(
        date.year, date.month, date.day, snapped ~/ 60, snapped % 60);
    await ref.read(tasksProvider.notifier).updateTask(task.copyWith(
        scheduledStart: start, durationMin: task.durationMin ?? 30));
    HapticFeedback.selectionClick();
  }

  /// Finger tracking during a block move: global Y + scroll offset → minute
  /// slot; global X + page offset → target day column. Near the viewport
  /// edges the grid auto-scrolls.
  void _onDragMove(String taskId, Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_v.hasClients) return;
    final local = box.globalToLocal(global);
    final topMin = (((local.dy + _v.offset) / _hourH * 60) - _grabMin)
        .clamp(0.0, 24 * 60 - 15.0);
    final colW = box.size.width / _visibleDays;
    final pageF = _days.page ?? _dayRange.toDouble();
    final dayIndex =
        (local.dx / colW + pageF).floor().clamp(0, 2 * _dayRange);
    _drag.value =
        (taskId: taskId, dayIndex: dayIndex, topMin: topMin.round());

    final screenH = MediaQuery.of(context).size.height;
    if (global.dy < 170 || global.dy > screenH - 240) {
      final dir = global.dy < 170 ? -10.0 : 10.0;
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (_v.hasClients) {
          _v.jumpTo(
              (_v.offset + dir).clamp(0.0, _v.position.maxScrollExtent));
        }
      });
    } else {
      _autoScroll?.cancel();
      _autoScroll = null;
    }
  }

  Future<void> _onDragEnd(String taskId) async {
    _autoScroll?.cancel();
    _autoScroll = null;
    final d = _drag.value;
    _drag.value = null;
    if (d == null) return;
    Task? task;
    for (final t in ref.read(tasksProvider).value ?? const <Task>[]) {
      if (t.id == taskId) task = t;
    }
    if (task == null) return;
    await _place(task, d.dayIndex, d.topMin);
  }

  Future<void> _onResizeEnd(String taskId) async {
    final r = _resize.value;
    _resize.value = null;
    if (r == null) return;
    Task? task;
    for (final t in ref.read(tasksProvider).value ?? const <Task>[]) {
      if (t.id == taskId) task = t;
    }
    if (task == null) return;
    await ref
        .read(tasksProvider.notifier)
        .updateTask(task.copyWith(durationMin: r.durMin));
    HapticFeedback.selectionClick();
  }

  /// Long-press on an empty slot → quick-create a task at that time.
  Future<void> _quickCreate(int dayIndex, int min) async {
    final date = _dateFor(dayIndex);
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'New task · ${date.day}/${date.month} '
            '${(min ~/ 60).toString().padLeft(2, '0')}:'
            '${(min % 60).toString().padLeft(2, '0')}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Task title'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(tasksProvider.notifier).addTask(
        title: title,
        scheduledStart:
            DateTime(date.year, date.month, date.day, min ~/ 60, min % 60),
        durationMin: 30);
    HapticFeedback.selectionClick();
  }

  /// Block callbacks bundle passed to each column (keeps ctor readable).
  void _blockDragStart(String taskId, double grabMin, Offset global) {
    HapticFeedback.mediumImpact();
    _grabMin = grabMin;
    _onDragMove(taskId, global);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksProvider).value ?? const [];
    final hours = ref.watch(workingHoursProvider);
    final barPad = MediaQuery.paddingOf(context).bottom;

    // Bucket tasks into page columns; open/locked unscheduled go to the tray.
    final scheduled = <int, List<Task>>{
      for (var i = 0; i <= 2 * _dayRange; i++) i: []
    };
    final unscheduled = <Task>[];
    for (final t in tasks) {
      final s = t.scheduledStart;
      if (s == null) {
        if (t.status != TaskStatus.done) unscheduled.add(t);
        continue;
      }
      final idx = _dayRange +
          DateTime(s.year, s.month, s.day).difference(_dateFor(_dayRange)).inDays;
      if (idx >= 0 && idx <= 2 * _dayRange) scheduled[idx]!.add(t);
    }

    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: Column(children: [
            // ---- Header ----
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, 0),
              child: Row(children: [
                Text('Schedule',
                    style: AppTypography.grotesk(theme.colorScheme.onSurface)
                        .copyWith(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _autoScheduleAll,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Auto'),
                ),
                IconButton(
                  tooltip: 'Working hours',
                  icon: const Icon(Icons.schedule_rounded, size: 20),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const WorkingHoursEditor())),
                ),
              ]),
            ),

            // ---- Day header strip (synced to the page offset) ----
            AnimatedBuilder(
              animation: _days,
              builder: (context, _) {
                final p = _days.hasClients
                    ? (_days.page ?? _dayRange.toDouble())
                    : _dayRange.toDouble();
                return Row(children: [
                  const SizedBox(width: _gutterW),
                  for (var i = 0; i < _visibleDays; i++)
                    Expanded(child: _DayHeaderCell(date: _dateFor(p.floor() + i))),
                ]);
              },
            ),
            const SizedBox(height: 4),

            // ---- Grid: gutter + paged day columns + now line ----
            Expanded(
              child: SingleChildScrollView(
                controller: _v,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _TimeGutter(),
                      Expanded(
                        child: RepaintBoundary(
                          child: SizedBox(
                            key: _gridKey,
                            height: 24 * _hourH,
                            child: Stack(children: [
                              PageView.builder(
                                controller: _days,
                                itemCount: 2 * _dayRange + 1,
                                itemBuilder: (context, i) => _DayColumn(
                                  date: _dateFor(i),
                                  dayIndex: i,
                                  tasks: scheduled[i] ?? const [],
                                  hours: hours,
                                  drag: _drag,
                                  resize: _resize,
                                  onQuickCreate: _quickCreate,
                                  onPlace: _place,
                                  onDragStart: _blockDragStart,
                                  onDragMove: _onDragMove,
                                  onDragEnd: _onDragEnd,
                                  onResizeTick: (id, dy) {
                                    // Accumulate finger travel → snapped
                                    // duration preview.
                                    _resizeDelta += dy / _hourH * 60;
                                    final task = (ref
                                                .read(tasksProvider)
                                                .value ??
                                            const <Task>[])
                                        .firstWhere((t) => t.id == id,
                                            orElse: () => _missingTask);
                                    if (task.id.isEmpty) return;
                                    final base = task.durationMin ?? 30;
                                    final next = ((base + _resizeDelta) / 15)
                                            .round() *
                                        15;
                                    _resize.value = (
                                      taskId: id,
                                      durMin: next < 15 ? 15 : next
                                    );
                                  },
                                  onResizeStart: () => _resizeDelta = 0,
                                  onResizeEnd: _onResizeEnd,
                                ),
                              ),
                              const IgnorePointer(child: _NowLine()),
                            ]),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),

            // ---- Unscheduled tray ----
            if (unscheduled.isNotEmpty)
              _UnscheduledTray(tasks: unscheduled, bottomPad: barPad),
          ]),
        ),
      ),
    );
  }
}

/// Sentinel for a lookup miss (never rendered).
final _missingTask =
    Task(id: '', title: '', description: '', createdAt: DateTime(0));

/// Left gutter with hour labels (12 AM … 11 PM), aligned to grid lines.
class _TimeGutter extends StatelessWidget {
  const _TimeGutter();

  static const _labels = [
    '12 AM', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11',
    '12 PM', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _gutterW,
      height: 24 * _hourH,
      child: Column(children: [
        for (var h = 0; h < 24; h++)
          SizedBox(
            height: _hourH,
            child: Align(
              alignment: const Alignment(0, -0.95),
              child: Text(_labels[h],
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
      ]),
    );
  }
}

/// Weekday letter + day number; today gets the accent filled circle.
class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({required this.date});
  final DateTime date;

  static const _wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_wd[date.weekday - 1],
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 2),
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isToday ? theme.colorScheme.primary : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text('${date.day}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isToday ? Colors.black : theme.colorScheme.onSurface,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    ]);
  }
}

/// Red "now" indicator spanning the grid — hairline + time pill on the left.
class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final top = (now.hour * 60 + now.minute) / 60 * _hourH;
    const red = Color(0xFFFF6B6B);
    return Positioned(
      top: top - 8,
      left: 0,
      right: 0,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: red,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}',
            style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 9),
          ),
        ),
        Expanded(child: Container(height: 1.4, color: red)),
      ]),
    );
  }
}

/// One day column: shaded background + hairlines (one CustomPaint), a
/// DragTarget for tray drops, long-press quick-create on empty space, and
/// positioned task blocks. While a block is being dragged this column shows
/// the ghost preview when it's the current target.
class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.date,
    required this.dayIndex,
    required this.tasks,
    required this.hours,
    required this.drag,
    required this.resize,
    required this.onQuickCreate,
    required this.onPlace,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeTick,
    required this.onResizeEnd,
  });

  final DateTime date;
  final int dayIndex;
  final List<Task> tasks;
  final WorkingHours hours;
  final ValueNotifier<DragPreview?> drag;
  final ValueNotifier<ResizePreview?> resize;
  final void Function(int dayIndex, int min) onQuickCreate;
  final void Function(Task task, int dayIndex, int topMin) onPlace;
  final void Function(String taskId, double grabMin, Offset global)
      onDragStart;
  final void Function(String taskId, Offset global) onDragMove;
  final void Function(String taskId) onDragEnd;
  final VoidCallback onResizeStart;
  final void Function(String taskId, double dy) onResizeTick;
  final void Function(String taskId) onResizeEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groups = ref.watch(groupsProvider);
    Color colorOf(Task t) {
      for (final g in groups) {
        if (g.id == t.groupId) return g.color;
      }
      return theme.colorScheme.primary;
    }

    final boxes = layoutDayBlocks([
      for (final t in tasks)
        (
          taskId: t.id,
          startMin:
              t.scheduledStart!.hour * 60 + t.scheduledStart!.minute,
          endMin: t.scheduledStart!.hour * 60 +
              t.scheduledStart!.minute +
              (t.durationMin ?? 30),
        ),
    ]);

    return DragTarget<Task>(
      onAcceptWithDetails: (d) {
        final box = context.findRenderObject()! as RenderBox;
        final local = box.globalToLocal(d.offset);
        onPlace(d.data, dayIndex, (local.dy / _hourH * 60).round());
      },
      builder: (context, candidates, rejects) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (d) => onQuickCreate(dayIndex,
              (d.localPosition.dy / _hourH * 60 / 15).floor() * 15),
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DayGridPainter(
                  date: date,
                  hours: hours,
                  lineColor: theme.colorScheme.outline,
                  shadeColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.035),
                  altColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.02),
                ),
              ),
            ),
            if (candidates.isNotEmpty)
              Positioned.fill(
                child: Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                ),
              ),
            for (final b in boxes)
              _ScheduledBlock(
                key: ValueKey(b.taskId),
                box: b,
                task: tasks.firstWhere((t) => t.id == b.taskId),
                color: colorOf(tasks.firstWhere((t) => t.id == b.taskId)),
                drag: drag,
                resize: resize,
                onDragStart: onDragStart,
                onDragMove: onDragMove,
                onDragEnd: onDragEnd,
                onResizeStart: onResizeStart,
                onResizeTick: onResizeTick,
                onResizeEnd: onResizeEnd,
              ),
            // Drag ghost — the moving block preview on the target column.
            ValueListenableBuilder(
              valueListenable: drag,
              builder: (context, d, _) {
                if (d == null || d.dayIndex != dayIndex) {
                  return const SizedBox.shrink();
                }
                Task? task;
                for (final t in ref.read(tasksProvider).value ??
                    const <Task>[]) {
                  if (t.id == d.taskId) task = t;
                }
                if (task == null) return const SizedBox.shrink();
                final dur = task.durationMin ?? 30;
                return Positioned(
                  left: 2,
                  right: 2,
                  top: d.topMin / 60 * _hourH,
                  height: (dur / 60 * _hourH).clamp(24.0, 24 * _hourH),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorOf(task).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: colorOf(task).withValues(alpha: 0.9),
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(6, 3, 4, 0),
                    child: Text(task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurface)),
                  ),
                );
              },
            ),
          ]),
        );
      },
    );
  }
}

/// Hour + half-hour hairlines, alternating-day tint, and light shading over
/// non-working hours — one painter per column (cheap, no widget spam).
class _DayGridPainter extends CustomPainter {
  const _DayGridPainter({
    required this.date,
    required this.hours,
    required this.lineColor,
    required this.shadeColor,
    required this.altColor,
  });

  final DateTime date;
  final WorkingHours hours;
  final Color lineColor;
  final Color shadeColor;
  final Color altColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Alternate day columns get a faint fill.
    if (date.day.isEven) {
      canvas.drawRect(Offset.zero & size, Paint()..color = altColor);
    }
    // Shade non-working hours for this weekday (gaps between ranges and
    // before/after them).
    final ranges = [...hours.rangesFor(date.weekday)]
      ..sort((a, b) => a.startMin - b.startMin);
    final shade = Paint()..color = shadeColor;
    if (!hours.isEnabled(date.weekday)) {
      canvas.drawRect(Offset.zero & size, shade); // day off → all shaded
    } else {
      var cursor = 0;
      for (final r in ranges) {
        if (r.startMin > cursor) {
          canvas.drawRect(
              Rect.fromLTRB(0, cursor / 60 * _hourH, size.width,
                  r.startMin / 60 * _hourH),
              shade);
        }
        if (r.endMin > cursor) cursor = r.endMin;
      }
      if (cursor < 1440) {
        canvas.drawRect(
            Rect.fromLTRB(
                0, cursor / 60 * _hourH, size.width, 24 * _hourH),
            shade);
      }
    }
    // Hour + half-hour hairlines.
    final line = Paint()
      ..color = lineColor.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    final half = Paint()
      ..color = lineColor.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    for (var h = 0; h <= 24; h++) {
      canvas.drawLine(
          Offset(0, h * _hourH), Offset(size.width, h * _hourH), line);
      if (h < 24) {
        canvas.drawLine(Offset(0, h * _hourH + _hourH / 2),
            Offset(size.width, h * _hourH + _hourH / 2), half);
      }
    }
  }

  @override
  bool shouldRepaint(_DayGridPainter old) =>
      old.date != date || old.hours != hours;
}

/// A scheduled task block: coloured by group, title on top, long-press to
/// lift & move (15-min snap + day targeting via ghost), bottom edge drag
/// resizes the duration.
class _ScheduledBlock extends StatelessWidget {
  const _ScheduledBlock({
    super.key,
    required this.box,
    required this.task,
    required this.color,
    required this.drag,
    required this.resize,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeTick,
    required this.onResizeEnd,
  });

  final BlockBox box;
  final Task task;
  final Color color;
  final ValueNotifier<DragPreview?> drag;
  final ValueNotifier<ResizePreview?> resize;
  final void Function(String taskId, double grabMin, Offset global)
      onDragStart;
  final void Function(String taskId, Offset global) onDragMove;
  final void Function(String taskId) onDragEnd;
  final VoidCallback onResizeStart;
  final void Function(String taskId, double dy) onResizeTick;
  final void Function(String taskId) onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: drag,
      builder: (context, d, _) => ValueListenableBuilder(
        valueListenable: resize,
        builder: (context, r, _) {
          final beingDragged = d?.taskId == task.id;
          final beingResized = r?.taskId == task.id;
          // While moving, the ghost owns this block — hide the original.
          if (beingDragged) return const SizedBox.shrink();
          final dur =
              beingResized ? r!.durMin : (task.durationMin ?? 30);
          return LayoutBuilder(builder: (context, c) {
            final laneW = c.maxWidth / box.lanes;
            return Positioned(
              left: box.lane * laneW + 1,
              top: box.startMin / 60 * _hourH,
              width: laneW - 2,
              height: (dur / 60 * _hourH).clamp(24.0, 24 * _hourH),
              child: Semantics(
                label: 'Scheduled task ${task.title}. '
                    'Long press to move, drag bottom edge to resize.',
                child: AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.fast),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: color.withValues(alpha: 0.55)),
                  ),
                  child: Stack(children: [
                    // Body — long-press to move; tap opens the detail.
                    Positioned.fill(
                      child: GestureDetector(
                        onLongPressStart: (det) => onDragStart(
                            task.id,
                            det.localPosition.dy / _hourH * 60,
                            det.globalPosition),
                        onLongPressMoveUpdate: (det) =>
                            onDragMove(task.id, det.globalPosition),
                        onLongPressEnd: (_) => onDragEnd(task.id),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    TaskDetailScreen(taskId: task.id))),
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(6, 3, 4, 0),
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                height: 1.15),
                          ),
                        ),
                      ),
                    ),
                    // Bottom resize handle.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 14,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => onResizeStart(),
                        onVerticalDragUpdate: (det) =>
                            onResizeTick(task.id, det.delta.dy),
                        onVerticalDragEnd: (_) => onResizeEnd(task.id),
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 3,
                            margin: const EdgeInsets.only(bottom: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          });
        },
      ),
    );
  }
}

/// Bottom strip of open tasks with no slot yet. Chips are
/// LongPressDraggable — drop one on a day column to schedule it there.
class _UnscheduledTray extends StatelessWidget {
  const _UnscheduledTray({required this.tasks, required this.bottomPad});
  final List<Task> tasks;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 64 + bottomPad + 70, // clear the floating tab bar
      padding: EdgeInsets.only(bottom: bottomPad + 70),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Text('UNSCHEDULED',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.4)),
            ),
          ),
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: LongPressDraggable<Task>(
                data: t,
                feedback: Material(
                  color: Colors.transparent,
                  child: _trayChip(theme, t, lifted: true),
                ),
                childWhenDragging: Opacity(
                    opacity: 0.3, child: _trayChip(theme, t)),
                child: _trayChip(theme, t),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trayChip(ThemeData theme, Task t, {bool lifted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
        boxShadow: lifted
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 8))
              ]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.drag_indicator_rounded,
            size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium),
        ),
      ]),
    );
  }
}
