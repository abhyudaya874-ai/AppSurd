/// Task + evidence data models. Hand-written JSON (no codegen) stored in the
/// `receipts_tasks` Hive box. `status` is the state machine the whole app
/// renders from: open → verifying → (done | locked → back to open).
library;

/// Lifecycle of a task. `locked` means an accountability challenge is pending.
enum TaskStatus { open, verifying, locked, done }

/// The four kinds of proof a user can submit.
enum EvidenceType { url, screenshot, text, commit }

/// One submitted piece of evidence plus its verdict (filled in phase 4).
class EvidenceAttempt {
  const EvidenceAttempt({
    required this.id,
    required this.type,
    required this.payload,
    required this.submittedAt,
    this.verdictJson,
  });

  final String id;
  final EvidenceType type;

  /// Meaning depends on [type]: URL string / local image path / written text /
  /// GitHub commit URL.
  final String payload;
  final DateTime submittedAt;

  /// Raw parsed verdict JSON map (kept for history rendering).
  final Map<String, dynamic>? verdictJson;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'payload': payload,
    'submittedAt': submittedAt.toIso8601String(),
    'verdictJson': verdictJson,
  };

  factory EvidenceAttempt.fromJson(Map<String, dynamic> json) =>
      EvidenceAttempt(
        id: json['id'] as String,
        type: EvidenceType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => EvidenceType.text,
        ),
        payload: json['payload'] as String? ?? '',
        submittedAt:
            DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
            DateTime.now(),
        verdictJson: (json['verdictJson'] as Map?)?.cast<String, dynamic>(),
      );
}

/// A task that can only be completed by verified evidence — there is no
/// "mark done" anywhere in the app by design.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.status = TaskStatus.open,
    this.attempts = const [],
    this.integrityDelta = 0,
    this.isDemo = false,
    this.groupId,
    this.dueAt,
    this.priority = 0,
    this.durationMin,
    this.scheduledStart,
  });

  final String id;
  final String title;

  /// "What counts as proof?" — shown to the verifier so it can judge fit.
  final String description;
  final DateTime createdAt;
  final TaskStatus status;
  final List<EvidenceAttempt> attempts;

  /// Running contribution of this task to the Integrity Score.
  final int integrityDelta;

  /// Marks seeded demo content (labelled "Demo data" in the UI).
  final bool isDemo;

  /// Optional group assignment (Personal / College / Work / custom).
  final String? groupId;

  /// Optional deadline — set from Create Task; used by due-date grouping and
  /// the schedule grid's "due" chips.
  final DateTime? dueAt;

  /// 0 = none, 1 = medium, 2 = high. Drives sort + auto-schedule order.
  final int priority;

  /// Planned length of a scheduled block; defaults to 30 in the scheduler.
  final int? durationMin;

  /// When the task sits on the Schedule grid; null = in the unscheduled tray.
  final DateTime? scheduledStart;

  /// When the task was verified — the last attempt's submission time. Null
  /// until the task reaches `done`; feeds the contribution heatmap.
  DateTime? get completedAt => status == TaskStatus.done && attempts.isNotEmpty
      ? attempts.last.submittedAt
      : null;

  Task copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    List<EvidenceAttempt>? attempts,
    int? integrityDelta,
    bool? isDemo,
    String? groupId,
    DateTime? dueAt,
    int? priority,
    int? durationMin,
    DateTime? scheduledStart,
    bool clearDueAt = false,
    bool clearDurationMin = false,
    bool clearScheduledStart = false,
    bool clearGroupId = false,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      integrityDelta: integrityDelta ?? this.integrityDelta,
      isDemo: isDemo ?? this.isDemo,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      priority: priority ?? this.priority,
      durationMin: clearDurationMin ? null : (durationMin ?? this.durationMin),
      scheduledStart: clearScheduledStart
          ? null
          : (scheduledStart ?? this.scheduledStart),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'attempts': [for (final a in attempts) a.toJson()],
    'integrityDelta': integrityDelta,
    'isDemo': isDemo,
    'groupId': groupId,
    'dueAt': dueAt?.toIso8601String(),
    'priority': priority,
    'durationMin': durationMin,
    'scheduledStart': scheduledStart?.toIso8601String(),
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    status: TaskStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => TaskStatus.open,
    ),
    attempts: [
      for (final a in (json['attempts'] as List? ?? const []))
        EvidenceAttempt.fromJson(Map<String, dynamic>.from(a as Map)),
    ],
    integrityDelta: (json['integrityDelta'] as num?)?.toInt() ?? 0,
    isDemo: json['isDemo'] as bool? ?? false,
    groupId: json['groupId'] as String?,
    dueAt: DateTime.tryParse(json['dueAt'] as String? ?? ''),
    priority: (json['priority'] as num?)?.toInt() ?? 0,
    durationMin: (json['durationMin'] as num?)?.toInt(),
    scheduledStart: DateTime.tryParse(json['scheduledStart'] as String? ?? ''),
  );
}
