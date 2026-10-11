// Unit tests for the profile contribution stats + completedAt model getter.

import 'package:flutter_test/flutter_test.dart';
import 'package:receipts/features/profile/contribution_stats.dart';
import 'package:receipts/features/tasks/task_model.dart';

void main() {
  Task doneAt(String id, DateTime when) => Task(
    id: id,
    title: id,
    description: '',
    createdAt: when,
    status: TaskStatus.done,
    attempts: [
      EvidenceAttempt(
        id: '$id-e',
        type: EvidenceType.text,
        payload: 'x',
        submittedAt: when,
        verdictJson: const {'status': 'pass'},
      ),
    ],
  );

  test('completedAt = last attempt time, only when done', () {
    final open = Task(
      id: 'o',
      title: 'o',
      description: '',
      createdAt: DateTime.now(),
    );
    expect(open.completedAt, isNull);
    final t = doneAt('d', DateTime(2026, 10, 5, 14));
    expect(t.completedAt, DateTime(2026, 10, 5, 14));
  });

  test('receiptsByDay counts verified tasks per day', () {
    final map = receiptsByDay([
      doneAt('a', DateTime(2026, 10, 10, 9)),
      doneAt('b', DateTime(2026, 10, 10, 20)),
      doneAt('c', DateTime(2026, 10, 11, 8)),
    ]);
    expect(map[DateTime(2026, 10, 10)], 2);
    expect(map[DateTime(2026, 10, 11)], 1);
  });

  test('computeStats: streaks, total, best day', () {
    final now = DateTime(2026, 10, 12, 18);
    final byDay = {
      DateTime(2026, 10, 8): 1,
      DateTime(2026, 10, 9): 2,
      DateTime(2026, 10, 10): 1, // 3-day run ending day before yesterday
      DateTime(2026, 10, 1): 5, // isolated best day
    };
    final s = computeStats(byDay, now);
    expect(s.total, 9);
    expect(s.longestStreak, 3);
    expect(s.currentStreak, 0); // yesterday (11th) empty → streak broken
    expect(s.bestDay, DateTime(2026, 10, 1));
    expect(s.bestCount, 5);
  });

  test('computeStats: today-empty does not break a live streak', () {
    final now = DateTime(2026, 10, 12, 18);
    final byDay = {DateTime(2026, 10, 10): 1, DateTime(2026, 10, 11): 2};
    expect(computeStats(byDay, now).currentStreak, 2);
  });

  test('computeStats: empty map → zeros', () {
    final s = computeStats(const {}, DateTime.now());
    expect(s.total, 0);
    expect(s.bestDay, isNull);
  });
}
