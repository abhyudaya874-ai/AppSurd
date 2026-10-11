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
    this.groupBy = TaskGroupBy.none,
    this.sortBy = TaskSortBy.activity,
    this.ascending = false,
  });

  final TaskGroupBy groupBy;
  final TaskSortBy sortBy;
  final bool ascending;

  TaskViewOptions copyWith(
          {TaskGroupBy? groupBy, TaskSortBy? sortBy, bool? ascending}) =>
      TaskViewOptions(
        groupBy: groupBy ?? this.groupBy,
        sortBy: sortBy ?? this.sortBy,
        ascending: ascending ?? this.ascending,
      );
}

/// Persisted view options (receipts_settings box). Pure fns below stay
/// UI-free so they're unit-testable.
final taskViewProvider =
    NotifierProvider<TaskViewNotifier, TaskViewOptions>(TaskViewNotifier.new);

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
            orElse: () => TaskGroupBy.none),
        sortBy: TaskSortBy.values.firstWhere(
            (s) => s.name == raw['sortBy'],
            orElse: () => TaskSortBy.activity),
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
DateTime lastActivity(Task t) => t.attempts.isEmpty
    ? t.createdAt
    : t.attempts.last.submittedAt;

/// Sorts a copy of [tasks] per [sortBy]; [ascending] flips the comparison.
List<Task> sortTasks(List<Task> tasks, TaskSortBy sortBy, bool ascending) {
  final list = [...tasks];
  int cmp(Task a, Task b) => switch (sortBy) {
        TaskSortBy.created => a.createdAt.compareTo(b.createdAt),
        TaskSortBy.due => _cmpNullable(a.dueAt, b.dueAt),
        TaskSortBy.title =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
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

/// Due-date bucket used by `Group by · Due date`.
String dueBucket(DateTime? dueAt, DateTime now) {
  if (dueAt == null) return 'No date';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final diff = day.difference(today).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff <= 7) return 'This week';
  return 'Later';
}

/// Buckets [tasks] into ordered sections per [groupBy]; section ordering is
/// fixed and human-meaningful (status lifecycle, due chronology, priority
/// high→low). Group buckets follow the user's group list order then Inbox.
List<TaskSection> groupTasks(
    List<Task> tasks, List<Group> groups, TaskGroupBy groupBy, DateTime now) {
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
      final inbox = tasks.where((t) =>
          t.groupId == null ||
          !groups.any((g) => g.id == t.groupId)).toList();
      if (inbox.isNotEmpty) sections.add(TaskSection('Inbox', inbox));
      return sections;
    case TaskGroupBy.due:
      const order = ['Today', 'Tomorrow', 'This week', 'Later', 'No date'];
      return [
        for (final b in order)
          if (tasks.any((t) => dueBucket(t.dueAt, now) == b))
            TaskSection(b,
                tasks.where((t) => dueBucket(t.dueAt, now) == b).toList()),
      ];
    case TaskGroupBy.priority:
      const order = [(2, 'High'), (1, 'Medium'), (0, 'No priority')];
      return [
        for (final (p, label) in order)
          if (tasks.any((t) => t.priority == p))
            TaskSection(
                label, tasks.where((t) => t.priority == p).toList()),
      ];
  }
}
