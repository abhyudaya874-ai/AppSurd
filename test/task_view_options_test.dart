// Unit tests for the Tasks tab's pure group/sort logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:receipts/features/tasks/task_model.dart';
import 'package:receipts/features/tasks/task_view_options.dart';

Task _t(
  String id, {
  String title = 't',
  TaskStatus status = TaskStatus.open,
  int priority = 0,
  DateTime? dueAt,
  String? groupId,
  DateTime? created,
}) => Task(
  id: id,
  title: title,
  description: '',
  createdAt: created ?? DateTime(2026, 10, 1),
  status: status,
  priority: priority,
  dueAt: dueAt,
  groupId: groupId,
);

void main() {
  final now = DateTime(2026, 10, 11, 12); // fixed "today" for due buckets

  group('sortTasks', () {
    test('sorts by title ascending / descending', () {
      final ts = [_t('a', title: 'Zebra'), _t('b', title: 'apple')];
      expect(sortTasks(ts, TaskSortBy.title, true).map((t) => t.id), [
        'b',
        'a',
      ]);
      expect(sortTasks(ts, TaskSortBy.title, false).map((t) => t.id), [
        'a',
        'b',
      ]);
    });

    test('priority descending puts high first', () {
      final ts = [_t('low'), _t('high', priority: 2), _t('med', priority: 1)];
      expect(sortTasks(ts, TaskSortBy.priority, false).map((t) => t.id), [
        'high',
        'med',
        'low',
      ]);
    });

    test('undated tasks sink in due-date sort', () {
      final ts = [
        _t('none'),
        _t('soon', dueAt: now),
        _t('late', dueAt: now.add(const Duration(days: 9))),
      ];
      expect(sortTasks(ts, TaskSortBy.due, true).map((t) => t.id), [
        'soon',
        'late',
        'none',
      ]);
    });
  });

  group('dueBucket', () {
    test('buckets correctly around today', () {
      expect(dueBucket(null, now), 'No date');
      expect(dueBucket(now, now), 'Today');
      expect(dueBucket(now.subtract(const Duration(days: 2)), now), 'Today');
      expect(dueBucket(now.add(const Duration(days: 1)), now), 'Tomorrow');
      expect(dueBucket(now.add(const Duration(days: 5)), now), 'This week');
      expect(dueBucket(now.add(const Duration(days: 20)), now), 'Later');
    });
  });

  group('groupTasks', () {
    test('none → single unlabeled section', () {
      final s = groupTasks([_t('a'), _t('b')], const [], TaskGroupBy.none, now);
      expect(s.length, 1);
      expect(s.first.tasks.length, 2);
    });

    test('status groups in lifecycle order, skips empties', () {
      final ts = [
        _t('a', status: TaskStatus.done),
        _t('b', status: TaskStatus.open),
        _t('c', status: TaskStatus.locked),
      ];
      final s = groupTasks(ts, const [], TaskGroupBy.status, now);
      expect(s.map((x) => x.label), ['Challenge pending', 'Open', 'Verified']);
    });

    test('due buckets appear in chronological order', () {
      final ts = [
        _t('none'),
        _t('later', dueAt: now.add(const Duration(days: 30))),
        _t('today', dueAt: now),
      ];
      final s = groupTasks(ts, const [], TaskGroupBy.due, now);
      expect(s.map((x) => x.label), ['Today', 'Later', 'No date']);
    });
  });
}
