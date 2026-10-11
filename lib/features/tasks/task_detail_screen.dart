import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../accountability/challenge_screen.dart';
import '../verification/verification_screen.dart';
import '../verification/verdict_model.dart';
import 'evidence_sheet.dart';
import 'task_model.dart';
import 'tasks_provider.dart';

/// Task detail — Hero'd from the card. Shows the attempt history and the
/// "Submit proof" action. There is deliberately NO plain complete button:
/// completion only comes from a `pass` verdict.
class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final task = ref.watch(taskByIdProvider(taskId));

    if (task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Task not found')),
      );
    }

    final locked = task.status == TaskStatus.locked;
    final done = task.status == TaskStatus.done;

    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Hero(
              tag: 'task-title-${task.id}',
              child: Material(
                type: MaterialType.transparency,
                child: Text(task.title,
                    style: theme.textTheme.headlineMedium),
              ),
            ),
            if (task.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Proof expected: ${task.description}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (task.isDemo)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('Demo data',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.tertiary)),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (done)
              _DoneBanner()
            else if (locked)
              _LockedBanner(task: task)
            else
              FilledButton.icon(
                onPressed: () => EvidenceSheet.show(context, task),
                icon: const Icon(Icons.upload_outlined),
                label: const Text('Submit proof'),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text('Attempts', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            if (task.attempts.isEmpty)
              Text('No evidence submitted yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant))
            else
              for (var i = 0; i < task.attempts.length; i++)
                FadeSlideIn(index: i, child: _AttemptTile(attempt: task.attempts[i])),
          ],
        ),
      ),
    );
  }
}

/// One submitted evidence attempt with its verdict chip.
class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.attempt});
  final EvidenceAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = attempt.verdictJson?['verdict'] as String?;
    final (chipLabel, chipColor) = switch (verdict) {
      'pass' => ('pass', theme.colorScheme.primary),
      'partial' => ('partial', theme.colorScheme.tertiary),
      'fail' => ('fail', theme.colorScheme.error),
      _ => ('pending', theme.colorScheme.onSurfaceVariant),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        dense: true,
        leading: Icon(switch (attempt.type) {
          EvidenceType.url => Icons.link,
          EvidenceType.screenshot => Icons.image_outlined,
          EvidenceType.text => Icons.notes,
          EvidenceType.commit => Icons.commit,
        }),
        title: Text(
          attempt.payload,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          attempt.type.name,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: AnimatedDefaultTextStyle(
          duration: AppMotion.fast,
          style: theme.textTheme.labelSmall!.copyWith(color: chipColor),
          child: Text(chipLabel),
        ),
      ),
    );
  }
}

/// Shown while a challenge is pending — button resumes the challenge stored
/// on the latest attempt's verdict.
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challengeJson = task.attempts.isEmpty
        ? null
        : task.attempts.last.verdictJson?['challenge'];
    final challenge = challengeJson is Map
        ? ChallengeDef.fromJson(challengeJson.cast<String, dynamic>())
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_outline, color: theme.colorScheme.tertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Accountability challenge pending — finish it to submit new evidence.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChallengeScreen(
                  challenge: challenge ??
                      const ChallengeDef(
                        title: 'Say it like you mean it',
                        instructions:
                            'Retype: I will submit real proof next time.',
                        seconds: 60,
                        kind: 'retype',
                      ),
                  taskId: task.id,
                ),
              ),
            ),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: Text(challenge == null
                ? 'Resume challenge'
                : 'Resume: ${challenge.title}'),
          ),
        ]),
      ),
    );
  }
}

/// Completed state.
class _DoneBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(Icons.verified, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Verified complete. Receipt earned.',
                style: theme.textTheme.bodyMedium),
          ),
        ]),
      ),
    );
  }
}

/// Kept for phase-4 navigation convenience.
void openVerification(BuildContext context, Task task, EvidenceAttempt attempt) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => VerificationScreen(taskId: task.id, attemptId: attempt.id),
  ));
}
