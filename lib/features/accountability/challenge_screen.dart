import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_router.dart';
import '../../core/ai/openai_compat_client.dart';
import '../../core/ai/prompts.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../model_picker/model_selection.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import '../verification/verdict_model.dart';
import 'countdown_ring.dart';
import '../tasks/evidence_sheet.dart';

/// Accountability challenge: retype / quiz / reupload, run against a live
/// countdown ring. Completing it unlocks the task for a fresh attempt and
/// pays a small integrity bonus.
class ChallengeScreen extends ConsumerStatefulWidget {
  const ChallengeScreen(
      {super.key, required this.challenge, required this.taskId});

  final ChallengeDef challenge;
  final String taskId;

  @override
  ConsumerState<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends ConsumerState<ChallengeScreen> {
  bool _expired = false;
  bool _completed = false;
  DateTime _started = DateTime.now();

  Future<void> _complete() async {
    if (_completed) return;
    setState(() => _completed = true);
    final task = ref.read(taskByIdProvider(widget.taskId));
    if (task != null) {
      // Fast-finish bonus: +2 if done in under half the allotted time.
      final fast =
          DateTime.now().difference(_started).inSeconds < widget.challenge.seconds / 2;
      await ref.read(tasksProvider.notifier).updateTask(task.copyWith(
            status: TaskStatus.open,
            integrityDelta: task.integrityDelta + (fast ? 2 : 0),
          ));
    }
    if (mounted) {
      await Future<void>.delayed(AppMotion.slow);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.challenge;
    return Scaffold(
      appBar: AppBar(title: Text(c.title)),
      body: ConstrainedContent(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(children: [
            Text(c.instructions,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            CountdownRing(
              totalSeconds: c.seconds,
              onFinished: () => setState(() => _expired = true),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: _expired && !_completed
                  ? _Expired(onRetry: () => setState(() {
                        _expired = false;
                        _started = DateTime.now();
                      }))
                  : _completed
                      ? _CompletedFlash()
                      : switch (c.kind) {
                          'quiz' => _QuizBody(
                              taskId: widget.taskId,
                              onPass: _complete),
                          'reupload' => _ReuploadBody(
                              taskId: widget.taskId, onPass: _complete),
                          _ => _RetypeBody(
                              instructions: c.instructions,
                              onPass: _complete),
                        },
            ),
          ]),
        ),
      ),
    );
  }
}

/// retype: type the commitment sentence exactly; per-character feedback.
class _RetypeBody extends StatefulWidget {
  const _RetypeBody({required this.instructions, required this.onPass});
  final String instructions;
  final VoidCallback onPass;

  @override
  State<_RetypeBody> createState() => _RetypeBodyState();
}

class _RetypeBodyState extends State<_RetypeBody> {
  final _ctrl = TextEditingController();

  /// The target sentence is derived from the instructions (kept verbatim by
  /// the model prompt), with a sane default.
  String get _target => widget.instructions.isNotEmpty
      ? widget.instructions
      : 'I will submit real evidence next time.';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _ctrl.text;
    final correct = _target.startsWith(typed);
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_target, style: theme.textTheme.titleMedium),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Type it exactly',
          errorText:
              typed.isNotEmpty && !correct ? 'Character mismatch' : null,
        ),
        onChanged: (v) {
          HapticFeedback.selectionClick();
          if (v == _target) widget.onPass();
          setState(() {});
        },
      ),
      const SizedBox(height: AppSpacing.sm),
      // Per-character progress bar — green prefix, red at first error.
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: _target.isEmpty ? 0 : typed.length / _target.length,
          minHeight: 6,
          color: correct
              ? theme.colorScheme.primary
              : theme.colorScheme.error,
          backgroundColor:
              theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
    ]);
  }
}

/// quiz: two model-generated questions about the task's subject.
class _QuizBody extends ConsumerStatefulWidget {
  const _QuizBody({required this.taskId, required this.onPass});
  final String taskId;
  final VoidCallback onPass;

  @override
  ConsumerState<_QuizBody> createState() => _QuizBodyState();
}

class _QuizItem {
  _QuizItem(this.q, this.options, this.answer);
  final String q;
  final List<String> options;
  final int answer;
}

class _QuizBodyState extends ConsumerState<_QuizBody> {
  List<_QuizItem>? _questions;
  int _answered = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Ask the router for two questions about the task subject; fall back to
  /// generic accountability questions if the call fails (demo-safe).
  Future<void> _load() async {
    final task = ref.read(taskByIdProvider(widget.taskId));
    final title = task?.title ?? 'the task';
    try {
      final keys = await ref.read(configuredKeysProvider.future);
      final sel = ref.read(modelSelectionProvider);
      final plan = const ModelRouter().plan(
        tier: sel.preset,
        keys: keys,
        aliveIds: ref.read(aliveModelsProvider).value ?? const {},
        speed: sel.speed,
        customModelId: sel.customModelId,
      );
      final outcome = await const ModelRouter().execute<String>(
        plan,
        (client, spec) => client.complete(
          model: spec.id,
          jsonMode: true,
          maxTokens: 500,
          messages: [
            const ChatMessage(role: 'system', content: quizSystem),
            ChatMessage.text('user', 'Task: $title'),
          ],
        ),
        keys,
      );
      final block = Verdict.extractJsonBlock(outcome.value);
      final json = jsonDecode(block!) as Map<String, dynamic>;
      final qs = [
        for (final q in (json['questions'] as List? ?? const []))
          if (q is Map)
            _QuizItem(
              q['q'] as String? ?? '',
              [for (final o in (q['options'] as List? ?? const [])) '$o'],
              (q['answer'] as num?)?.toInt() ?? 0,
            ),
      ];
      if (qs.length >= 2 && mounted) setState(() => _questions = qs.take(2).toList());
    } catch (_) {
      if (mounted) setState(() => _questions = _fallback());
    }
    if (_questions == null && mounted) setState(() => _questions = _fallback());
  }

  List<_QuizItem> _fallback() => [
        _QuizItem('What does this app require before a task counts as done?',
            ['Good intentions', 'Verified evidence', 'A strong vibe'], 1),
        _QuizItem('Your last evidence was rejected. What unlocks the task?',
            ['Completing this challenge', 'Waiting politely', 'Nothing'], 0),
      ];

  void _answer(int qIndex, int option) {
    final q = _questions![qIndex];
    if (option == q.answer) {
      HapticFeedback.lightImpact();
      setState(() => _answered++);
      if (_answered >= 2) widget.onPass();
    } else {
      HapticFeedback.mediumImpact();
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_questions == null) {
      return const Center(child: _ThinkingDots());
    }
    return ListView(children: [
      for (var qi = 0; qi < _questions!.length; qi++) ...[
        Text('Q${qi + 1}. ${_questions![qi].q}',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (var oi = 0; oi < _questions![qi].options.length; oi++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs + 2),
            child: OutlinedButton(
              onPressed: () => _answer(qi, oi),
              child: Text(_questions![qi].options[oi]),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (_failed)
        Text('One wrong — the other question still counts. Keep going.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.tertiary)),
    ]);
  }
}

/// reupload: a countdown window to submit stronger evidence via the sheet.
/// Completes automatically once a new attempt lands (the sheet adds one and
/// flips the task to `verifying`).
class _ReuploadBody extends ConsumerWidget {
  const _ReuploadBody({required this.taskId, required this.onPass});
  final String taskId;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final task = ref.watch(taskByIdProvider(taskId));
    if (task != null && task.status == TaskStatus.verifying) {
      // New evidence submitted during the countdown — challenge satisfied.
      WidgetsBinding.instance.addPostFrameCallback((_) => onPass());
    }
    return Column(children: [
      Text('The clock is running. Bring better evidence.',
          style: theme.textTheme.bodyMedium),
      const SizedBox(height: AppSpacing.md),
      FilledButton.icon(
        onPressed: task == null
            ? null
            : () => EvidenceSheet.show(context, task),
        icon: const Icon(Icons.upload_outlined),
        label: const Text('Submit stronger evidence'),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text('Submitting new evidence ends this challenge.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _Expired extends StatelessWidget {
  const _Expired({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Text('Time ran out. The task stays locked.',
          style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      TextButton(onPressed: onRetry, child: const Text('Try again')),
    ]);
  }
}

class _CompletedFlash extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_open, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: AppSpacing.sm),
        Text('Unlocked. Bring receipts.', style: theme.textTheme.titleLarge),
      ]),
    );
  }
}

/// Three-dot typing indicator — shimmer, not a bare spinner.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            // Each dot peaks a third of a cycle after the previous one.
            child: Opacity(
              opacity: 0.3 +
                  0.7 *
                      (0.5 +
                          0.5 *
                              sin(((_c.value - i / 3) % 1.0) *
                                  2 *
                                  3.14159)),
              child: CircleAvatar(radius: 4, backgroundColor: color),
            ),
          ),
      ]),
    );
  }
}
