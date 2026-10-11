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
        type: EvidenceType.values
            .firstWhere((t) => t.name == json['type'], orElse: () => EvidenceType.text),
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

  Task copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    List<EvidenceAttempt>? attempts,
    int? integrityDelta,
    bool? isDemo,
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
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        status: TaskStatus.values
            .firstWhere((s) => s.name == json['status'], orElse: () => TaskStatus.open),
        attempts: [
          for (final a in (json['attempts'] as List? ?? const []))
            EvidenceAttempt.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        integrityDelta: (json['integrityDelta'] as num?)?.toInt() ?? 0,
        isDemo: json['isDemo'] as bool? ?? false,
      );
}
