import '../tasks/task_model.dart';

/// Contribution stats over a set of days → count. Pure functions so the
/// streak maths is unit-testable and explainable in Q&A.
///
/// [byDay] maps a day (truncated to midnight) to verified count that day.
class ContributionStats {
  const ContributionStats({
    required this.currentStreak,
    required this.longestStreak,
    required this.total,
    required this.bestDay,
    required this.bestCount,
  });

  /// Days in a row ending today (or yesterday if today is still empty).
  final int currentStreak;
  final int longestStreak;
  final int total;

  /// Day with the most verifications (null when the map is empty).
  final DateTime? bestDay;
  final int bestCount;
}

/// Truncates a timestamp to its calendar day.
DateTime dayKey(DateTime t) => DateTime(t.year, t.month, t.day);

/// Builds the day→count map from tasks' [Task.completedAt].
Map<DateTime, int> receiptsByDay(Iterable<Task> tasks) {
  final map = <DateTime, int>{};
  for (final t in tasks) {
    final c = t.completedAt;
    if (c != null) map.update(dayKey(c), (v) => v + 1, ifAbsent: () => 1);
  }
  return map;
}

/// Computes streaks/total/best-day from a day→count map.
ContributionStats computeStats(Map<DateTime, int> byDay, DateTime now) {
  if (byDay.isEmpty) {
    return const ContributionStats(
      currentStreak: 0,
      longestStreak: 0,
      total: 0,
      bestDay: null,
      bestCount: 0,
    );
  }
  var total = 0;
  DateTime? best;
  var bestCount = 0;
  for (final e in byDay.entries) {
    total += e.value;
    if (e.value > bestCount) {
      bestCount = e.value;
      best = e.key;
    }
  }
  // Longest streak: sort days, walk consecutive runs.
  final days = byDay.keys.toList()..sort();
  var longest = 1;
  var run = 1;
  for (var i = 1; i < days.length; i++) {
    if (days[i].difference(days[i - 1]).inDays == 1) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 1;
    }
  }
  // Current streak: count back from today; an empty today doesn't break it
  // (the day isn't over).
  var cur = 0;
  var cursor = dayKey(now);
  if ((byDay[cursor] ?? 0) == 0) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  while ((byDay[cursor] ?? 0) > 0) {
    cur++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return ContributionStats(
    currentStreak: cur,
    longestStreak: longest,
    total: total,
    bestDay: best,
    bestCount: bestCount,
  );
}
