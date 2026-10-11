// Unit tests for the schedule helpers: working-hours validation, the greedy
// auto-scheduler, and the overlap-aware block layout.

import 'package:flutter_test/flutter_test.dart';
import 'package:receipts/features/schedule/auto_schedule.dart';
import 'package:receipts/features/schedule/block_layout.dart';
import 'package:receipts/features/schedule/working_hours.dart';
import 'package:receipts/features/tasks/task_model.dart';

void main() {
  group('validateRanges', () {
    test('rejects end<=start and overlaps', () {
      expect(validateRanges([const TimeRange(60, 30)]), isNotNull);
      expect(
        validateRanges([const TimeRange(60, 120), const TimeRange(90, 200)]),
        isNotNull,
      );
      expect(
        validateRanges([const TimeRange(60, 120), const TimeRange(180, 240)]),
        isNull,
      );
    });
  });

  group('WorkingHours', () {
    test('covers only enabled ranges', () {
      const h = WorkingHours({
        1: [TimeRange(540, 600)], // Mon 9:00-10:00
      });
      expect(h.covers(1, 570), isTrue);
      expect(h.covers(1, 610), isFalse);
      expect(h.covers(2, 570), isFalse);
      expect(h.isEnabled(2), isFalse);
    });
  });

  group('autoSchedule', () {
    Task mk(
      String id, {
      int priority = 0,
      DateTime? due,
      int? dur,
      DateTime? start,
    }) => Task(
      id: id,
      title: id,
      description: '',
      createdAt: DateTime(2026, 10, 10),
      priority: priority,
      dueAt: due,
      durationMin: dur,
      scheduledStart: start,
    );

    // Monday 2026-10-12 (weekday 1), 09:00-11:00 only.
    final hours = const WorkingHours({
      1: [TimeRange(540, 660)],
    });
    final from = DateTime(2026, 10, 12, 8); // before the window

    test('places by priority within working hours, no overlaps', () {
      final tasks = [
        mk('low', dur: 60),
        mk('high', priority: 2, dur: 60),
        mk('med', priority: 1, dur: 60),
      ];
      final out = autoSchedule(tasks: tasks, hours: hours, from: from);
      expect(out.length, 3);
      expect(out.first.taskId, 'high'); // priority order
      expect(out.first.start, DateTime(2026, 10, 12, 9)); // window start
      // No two placements overlap.
      final sorted = [...out]..sort((a, b) => a.start.compareTo(b.start));
      for (var i = 1; i < sorted.length; i++) {
        final prevEnd = sorted[i - 1].start.add(
          Duration(minutes: sorted[i - 1].durationMin),
        );
        expect(sorted[i].start.isBefore(prevEnd), isFalse);
      }
    });

    test('avoids already-scheduled blocks', () {
      final taken = mk('taken', start: DateTime(2026, 10, 12, 9), dur: 60);
      final out = autoSchedule(
        tasks: [taken, mk('free', dur: 30)],
        hours: hours,
        from: from,
      );
      expect(out.single.taskId, 'free');
      expect(out.single.start, DateTime(2026, 10, 12, 10));
    });

    test('done tasks are skipped', () {
      final done = mk('done', dur: 30).copyWith(status: TaskStatus.done);
      final out = autoSchedule(tasks: [done], hours: hours, from: from);
      expect(out, isEmpty);
    });
  });

  group('layoutDayBlocks', () {
    test('non-overlapping blocks get lane 0 / 1 lane', () {
      final boxes = layoutDayBlocks([
        (taskId: 'a', startMin: 60, endMin: 120),
        (taskId: 'b', startMin: 180, endMin: 240),
      ]);
      expect(boxes.every((b) => b.lane == 0 && b.lanes == 1), isTrue);
    });

    test('overlapping blocks get distinct lanes and shared lane count', () {
      final boxes = layoutDayBlocks([
        (taskId: 'a', startMin: 60, endMin: 200),
        (taskId: 'b', startMin: 120, endMin: 180),
        (taskId: 'c', startMin: 150, endMin: 300),
      ]);
      final a = boxes.firstWhere((b) => b.taskId == 'a');
      final b = boxes.firstWhere((b) => b.taskId == 'b');
      final c = boxes.firstWhere((b) => b.taskId == 'c');
      expect(a.lane, 0);
      expect(b.lane, 1);
      expect(c.lane, 2); // c overlaps both a and b → needs its own lane
      expect(b.lanes, greaterThanOrEqualTo(2));
      expect(c.lanes, 3);
    });
  });
}
