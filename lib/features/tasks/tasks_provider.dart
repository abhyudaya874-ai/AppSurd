// READ THIS FIRST — every mutation writes through to Hive. done is only
// reachable via attachVerdict(pass); locked only via partial/fail.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import 'task_model.dart';

/// The task list, persisted to Hive. Every mutation writes straight through —
/// tasks must survive a restart mid-demo.
final tasksProvider = AsyncNotifierProvider<TasksNotifier, List<Task>>(
  TasksNotifier.new,
);

/// CRUD + persistence for tasks; also owns the Integrity Score derived state.
class TasksNotifier extends AsyncNotifier<List<Task>> {
  static const _boxName = 'receipts_tasks';
  static const _uuid = Uuid();

  /// Fixed id for the always-present demo task — "prove it with any photo".
  /// Pinned, labelled Demo, and verified by a deterministic local path so
  /// the hackathon demo works onstage with zero keys and no network.
  static const demoPhotoTaskId = 'demo-photo-receipt';

  @override
  Future<List<Task>> build() async {
    final box = await Hive.openBox(_boxName);
    await ensureDemoPhotoTask(box);
    return [
      for (final key in box.keys)
        Task.fromJson(Map<String, dynamic>.from(box.get(key) as Map)),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Creates the demo task once (idempotent — safe to call on every load
  /// and from Profile's 'Reset demo data').
  Future<void> ensureDemoPhotoTask(Box box) async {
    if (box.containsKey(demoPhotoTaskId)) return;
    await box.put(
      demoPhotoTaskId,
      Task(
        id: demoPhotoTaskId,
        title: 'Demo: prove it with any photo',
        description:
            'Upload any photo — the demo verifier accepts it. '
            '(Real tasks are judged by real models.)',
        createdAt: DateTime.now(),
        isDemo: true,
        pinned: true,
      ).toJson(),
    );
  }

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<void> _persist(Task task) async {
    final box = await _box();
    await box.put(task.id, task.toJson());
    state = AsyncData(await build());
  }

  /// Adds a task and returns it so the caller can navigate to its detail.
  /// Scheduling fields are optional — Create Task sets them, the quick
  /// composer leaves them null.
  Future<Task> addTask({
    required String title,
    String description = '',
    String? groupId,
    DateTime? dueAt,
    int priority = 0,
    int? durationMin,
    DateTime? scheduledStart,
  }) async {
    final task = Task(
      id: _uuid.v4(),
      title: title,
      description: description,
      createdAt: DateTime.now(),
      groupId: groupId,
      dueAt: dueAt,
      priority: priority,
      durationMin: durationMin,
      scheduledStart: scheduledStart,
    );
    await _persist(task);
    return task;
  }

  Future<void> deleteTask(String id) async {
    final box = await _box();
    await box.delete(id);
    state = AsyncData(await build());
  }

  /// Re-inserts a deleted task (Undo snackbar support).
  Future<void> restoreTask(Task task) => _persist(task);

  Future<void> updateTask(Task task) => _persist(task);

  /// Appends an evidence attempt and sets status (usually `verifying`).
  Future<void> addAttempt(
    String taskId,
    EvidenceAttempt attempt, {
    TaskStatus status = TaskStatus.verifying,
  }) async {
    final task = _find(taskId);
    if (task == null) return;
    await _persist(
      task.copyWith(status: status, attempts: [...task.attempts, attempt]),
    );
  }

  /// Attaches the parsed verdict to the latest attempt.
  Future<void> attachVerdict(
    String taskId,
    Map<String, dynamic> verdictJson, {
    required TaskStatus status,
    int integrityDelta = 0,
  }) async {
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
    await _persist(
      task.copyWith(
        status: status,
        integrityDelta: task.integrityDelta + integrityDelta,
        attempts: [
          ...task.attempts.sublist(0, task.attempts.length - 1),
          updated,
        ],
      ),
    );
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
