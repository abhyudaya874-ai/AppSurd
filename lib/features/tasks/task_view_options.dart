import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import 'group_model.dart';
import 'task_model.dart';

/// How the Tasks tab buckets rows. Persisted so the list reopens the way
/// the user left it.
enum TaskGroupBy { none, status, group, due, priority }

/// What the Tasks tab sorts by inside each bucket.
enum TaskSortBy { created, due, title, activity, priority }

/// One labelled section of the list (e.g. "Today", "College").
class TaskSection {
  const TaskSection(this.label, this.tasks);
  final String label;
  final List<Task> tasks;
}

/// Immutable view options record — read/written via [taskViewProvider].
class TaskViewOptions {
  const TaskViewOptions({
    this.groupBy = TaskGroupBy.due,
    this.sortBy = TaskSortBy.activity,
    this.ascending = false,
  });

  final TaskGroupBy groupBy;
  final TaskSortBy sortBy;
  final bool ascending;

  TaskViewOptions copyWith({
    TaskGroupBy? groupBy,
    TaskSortBy? sortBy,
    bool? ascending,
  }) => TaskViewOptions(
    groupBy: groupBy ?? this.groupBy,
    sortBy: sortBy ?? this.sortBy,
    ascending: ascending ?? this.ascending,
  );
}

/// Persisted view options (receipts_settings box). Pure fns below stay
/// UI-free so they're unit-testable.
final taskViewProvider = NotifierProvider<TaskViewNotifier, TaskViewOptions>(
  TaskViewNotifier.new,
);

class TaskViewNotifier extends Notifier<TaskViewOptions> {
  static const _boxName = 'receipts_settings';
  static const _key = 'taskView';

  @override
  TaskViewOptions build() {
    _load();
    return const TaskViewOptions();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final raw = box.get(_key);
    if (raw is Map) {
      state = TaskViewOptions(
        groupBy: TaskGroupBy.values.firstWhere(
          (g) => g.name == raw['groupBy'],
          orElse: () => TaskGroupBy.due,
        ),
        sortBy: TaskSortBy.values.firstWhere(
          (s) => s.name == raw['sortBy'],
          orElse: () => TaskSortBy.activity,
        ),
        ascending: raw['ascending'] as bool? ?? false,
      );
    }
  }

  Future<void> set(TaskViewOptions v) async {
    state = v;
    final box = await Hive.openBox(_boxName);
    await box.put(_key, {
      'groupBy': v.groupBy.name,
      'sortBy': v.sortBy.name,
      'ascending': v.ascending,
    });
  }
}

/// A task's most recent timestamp — last attempt's submission, else created.
/// Feeds the "Last activity" sort.
DateTime lastActivity(Task t) =>
    t.attempts.isEmpty ? t.createdAt : t.attempts.last.submittedAt;

/// Sorts a copy of [tasks] per [sortBy]; [ascending] flips the comparison.
List<Task> sortTasks(List<Task> tasks, TaskSortBy sortBy, bool ascending) {
  final list = [...tasks];
  int cmp(Task a, Task b) => switch (sortBy) {
    TaskSortBy.created => a.createdAt.compareTo(b.createdAt),
    TaskSortBy.due => _cmpNullable(a.dueAt, b.dueAt),
    TaskSortBy.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    TaskSortBy.activity => lastActivity(a).compareTo(lastActivity(b)),
    TaskSortBy.priority => a.priority.compareTo(b.priority),
  };
  list.sort((a, b) => ascending ? cmp(a, b) : -cmp(a, b));
  return list;
}

/// Nulls always sink to the end regardless of direction.
int _cmpNullable(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // descending flips sign — handled by caller
  if (b == null) return -1;
  return a.compareTo(b);
}

/// Short weekday + month names for due-date section headers — hand-rolled
/// so we don't pull in `intl` just for this.
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
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

/// Due-date section for a task — `(sortKey, label)`. Overdue+today →
/// 'Today', tomorrow → 'Tomorrow', the rest of the week one section per day
/// ('Mon 13 Oct'), anything further out lumps into its month ('Oct 2026'),
/// undated sinks to 'No date' (key 99999999).
(int, String) dueSection(DateTime? dueAt, DateTime now) {
  if (dueAt == null) return (99999999, 'No date');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final diff = day.difference(today).inDays;
  if (diff <= 0) return (-1, 'Today'); // key -1 sorts before everything
  if (diff == 1) return (0, 'Tomorrow');
  if (diff <= 6) {
    return (
      day.year * 10000 + day.month * 100 + day.day,
      '${_wd[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}',
    );
  }
  return (
    day.year * 10000 + day.month * 100,
    '${_months[day.month - 1]} ${day.year}',
  );
}

/// Label only — kept for the popover + tests.
String dueBucket(DateTime? dueAt, DateTime now) => dueSection(dueAt, now).$2;

/// Buckets [tasks] into ordered sections per [groupBy]; section ordering is
/// fixed and human-meaningful (status lifecycle, due chronology, priority
/// high→low). Group buckets follow the user's group list order then Inbox.
List<TaskSection> groupTasks(
  List<Task> tasks,
  List<Group> groups,
  TaskGroupBy groupBy,
  DateTime now,
) {
  switch (groupBy) {
    case TaskGroupBy.none:
      return [TaskSection('', tasks)];
    case TaskGroupBy.status:
      const order = [
        (TaskStatus.verifying, 'Verifying'),
        (TaskStatus.locked, 'Challenge pending'),
        (TaskStatus.open, 'Open'),
        (TaskStatus.done, 'Verified'),
      ];
      return [
        for (final (s, label) in order)
          if (tasks.any((t) => t.status == s))
            TaskSection(label, tasks.where((t) => t.status == s).toList()),
      ];
    case TaskGroupBy.group:
      final sections = <TaskSection>[];
      for (final g in groups) {
        final inGroup = tasks.where((t) => t.groupId == g.id).toList();
        if (inGroup.isNotEmpty) sections.add(TaskSection(g.name, inGroup));
      }
      final inbox = tasks
          .where(
            (t) => t.groupId == null || !groups.any((g) => g.id == t.groupId),
          )
          .toList();
      if (inbox.isNotEmpty) sections.add(TaskSection('Inbox', inbox));
      return sections;
    case TaskGroupBy.due:
      // Bucket by sort key so day/month sections stay chronological; the
      // key also decides which tasks share one header.
      final byKey = <int, List<Task>>{};
      for (final t in tasks) {
        byKey.putIfAbsent(dueSection(t.dueAt, now).$1, () => []).add(t);
      }
      final keys = byKey.keys.toList()..sort();
      return [
        for (final k in keys)
          TaskSection(dueSection(byKey[k]!.first.dueAt, now).$2, byKey[k]!),
      ];
    case TaskGroupBy.priority:
      const order = [(2, 'High'), (1, 'Medium'), (0, 'No priority')];
      return [
        for (final (p, label) in order)
          if (tasks.any((t) => t.priority == p))
            TaskSection(label, tasks.where((t) => t.priority == p).toList()),
      ];
  }
}
