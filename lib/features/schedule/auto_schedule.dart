import '../tasks/task_model.dart';
import 'working_hours.dart';

/// Where the auto-scheduler wants to put a task.
class Placement {
  const Placement({
    required this.taskId,
    required this.start,
    required this.durationMin,
  });
  final String taskId;
  final DateTime start;
  final int durationMin;
}

/// Greedy deterministic auto-scheduler: open tasks without a scheduledStart
/// are placed into the earliest free working-hours slots, highest priority
/// first, ties broken by soonest due date then creation order. Free = inside
/// a working range and not overlapping an already-scheduled block.
///
/// Pure function — unit-tested; the screen applies results via updateTask.
List<Placement> autoSchedule({
  required List<Task> tasks,
  required WorkingHours hours,
  DateTime? from,
  int days = 14,
  int defaultDuration = 30,
}) {
  final now = from ?? DateTime.now();
  // Candidates: open or locked (still need doing), no slot yet.
  final pending =
      tasks
          .where(
            (t) =>
                t.scheduledStart == null &&
                (t.status == TaskStatus.open || t.status == TaskStatus.locked),
          )
          .toList()
        ..sort((a, b) {
          final p = b.priority.compareTo(a.priority); // high first
          if (p != 0) return p;
          final ad = a.dueAt, bd = b.dueAt;
          if (ad != null && bd != null) {
            final c = ad.compareTo(bd);
            if (c != 0) return c;
          } else if (ad != null) {
            return -1; // dated before undated
          } else if (bd != null) {
            return 1;
          }
          return a.createdAt.compareTo(b.createdAt);
        });

  // Busy intervals per day (existing scheduled blocks).
  final busy = <DateTime, List<(int, int)>>{};
  void occupy(DateTime start, int durationMin) {
    final day = DateTime(start.year, start.month, start.day);
    busy.putIfAbsent(day, () => []).add((
      start.hour * 60 + start.minute,
      start.hour * 60 + start.minute + durationMin,
    ));
  }

  for (final t in tasks) {
    final s = t.scheduledStart;
    if (s != null) occupy(s, t.durationMin ?? defaultDuration);
  }

  final out = <Placement>[];
  for (final t in pending) {
    final dur = t.durationMin ?? defaultDuration;
    DateTime? placed;
    for (var d = 0; d < days && placed == null; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final ranges = hours.rangesFor(day.weekday);
      for (final r in ranges) {
        // Earliest candidate inside this range = range start, but not in
        // the past when the day is today.
        var candidate = r.startMin;
        if (d == 0) {
          final nowMin = now.hour * 60 + now.minute;
          candidate = candidate > nowMin
              ? candidate
              : ((nowMin + 14) ~/ 15) * 15;
        }
        while (candidate + dur <= r.endMin) {
          final clash = (busy[day] ?? const []).any(
            (b) => candidate < b.$2 && b.$1 < candidate + dur,
          );
          if (!clash) {
            placed = DateTime(
              day.year,
              day.month,
              day.day,
              candidate ~/ 60,
              candidate % 60,
            );
            break;
          }
          candidate += 15; // scan in 15-min steps — matches drag snap
        }
        if (placed != null) break;
      }
    }
    if (placed != null) {
      out.add(Placement(taskId: t.id, start: placed, durationMin: dur));
      occupy(placed, dur);
    }
  }
  return out;
}
