import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import 'task_model.dart';

/// The task list, persisted to Hive. Every mutation writes straight through —
/// tasks must survive a restart mid-demo.
final tasksProvider =
    AsyncNotifierProvider<TasksNotifier, List<Task>>(TasksNotifier.new);

/// CRUD + persistence for tasks; also owns the Integrity Score derived state.
class TasksNotifier extends AsyncNotifier<List<Task>> {
  static const _boxName = 'receipts_tasks';
  static const _uuid = Uuid();

  @override
  Future<List<Task>> build() async {
    final box = await Hive.openBox(_boxName);
    final tasks = [
      for (final key in box.keys)
        Task.fromJson(Map<String, dynamic>.from(box.get(key) as Map)),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<void> _persist(Task task) async {
    final box = await _box();
    await box.put(task.id, task.toJson());
    state = AsyncData(await build());
  }

  /// Adds a task and returns it so the caller can navigate to its detail.
  Future<Task> addTask({required String title, String description = ''}) async {
    final task = Task(
      id: _uuid.v4(),
      title: title,
      description: description,
      createdAt: DateTime.now(),
    );
    await _persist(task);
    return task;
  }

  Future<void> deleteTask(String id) async {
    final box = await _box();
    await box.delete(id);
    state = AsyncData(await build());
  }

  Future<void> updateTask(Task task) => _persist(task);

  /// Appends an evidence attempt and sets status (usually `verifying`).
  Future<void> addAttempt(String taskId, EvidenceAttempt attempt,
      {TaskStatus status = TaskStatus.verifying}) async {
    final task = _find(taskId);
    if (task == null) return;
    await _persist(task.copyWith(
      status: status,
      attempts: [...task.attempts, attempt],
    ));
  }

  /// Attaches the parsed verdict to the latest attempt.
  Future<void> attachVerdict(String taskId, Map<String, dynamic> verdictJson,
      {required TaskStatus status, int integrityDelta = 0}) async {
    final task = _find(taskId);
    if (task == null || task.attempts.isEmpty) return;
    final last = task.attempts.last;
    final updated = EvidenceAttempt(
      id: last.id,
      type: last.type,
      payload: last.payload,
      submittedAt: last.submittedAt,
      verdictJson: verdictJson,
    );
    await _persist(task.copyWith(
      status: status,
      integrityDelta: task.integrityDelta + integrityDelta,
      attempts: [...task.attempts.sublist(0, task.attempts.length - 1), updated],
    ));
  }

  Task? _find(String id) {
    final list = state.value;
    if (list == null) return null;
    for (final t in list) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Integrity Score: base 50 plus every task's integrityDelta, shown as an
/// animated counter in the list header.
final integrityScoreProvider = Provider<int>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  var score = 50;
  for (final t in tasks) {
    score += t.integrityDelta;
  }
  return score.clamp(0, 999);
});

/// True while any task is locked behind a challenge — other cards show the
/// "unresolved accountability" badge.
final anyLockedProvider = Provider<bool>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  return tasks.any((t) => t.status == TaskStatus.locked);
});

/// A single task lookup by id (for the detail screen).
final taskByIdProvider = Provider.family<Task?, String>((ref, id) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  for (final t in tasks) {
    if (t.id == id) return t;
  }
  return null;
});
