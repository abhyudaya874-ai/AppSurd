import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/transitions.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../settings/settings_screen.dart';
import '../playground/playground_screen.dart';
import 'add_task_sheet.dart';
import 'task_card.dart';
import 'task_detail_screen.dart';
import 'task_model.dart';
import 'tasks_provider.dart';

/// Home screen — the proof-or-it-didn't-happen task list. Animated entries,
/// swipe-to-delete with undo, and the Integrity Score chip in the header.
class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipts'),
        actions: [
          const _IntegrityChip(),
          IconButton(
            tooltip: 'Agent playground',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => Navigator.of(context)
                .push(AppTransitions.sharedAxis(const PlaygroundScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(AppTransitions.sharedAxis(const SettingsScreen())),
          ),
        ],
      ),
      body: ConstrainedContent(
        child: tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Could not load tasks.',
                style: theme.textTheme.bodyMedium),
          ),
          data: (tasks) => tasks.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final task = tasks[i];
                    return FadeSlideIn(
                      index: i,
                      child: Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Dismissible(
                          key: ValueKey(task.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(
                                right: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.delete_outline,
                                color: theme.colorScheme.error),
                          ),
                          onDismissed: (_) {
                            ref
                                .read(tasksProvider.notifier)
                                .deleteTask(task.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Task deleted')),
                            );
                          },
                          child: TaskCard(
                            task: task,
                            // Small "unresolved accountability" nudge while
                            // some other task is locked.
                            accountabilityPending: task.status !=
                                    TaskStatus.locked &&
                                ref.watch(anyLockedProvider),
                            onTap: () => Navigator.of(context).push(
                              AppTransitions.sharedAxis(
                                  TaskDetailScreen(taskId: task.id)),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddTaskSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }
}

/// Animated integrity-score counter in the app bar.
class _IntegrityChip extends ConsumerWidget {
  const _IntegrityChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(integrityScoreProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(Icons.verified_outlined,
            size: 16, color: theme.colorScheme.primary),
        label: TweenAnimationBuilder<double>(
          tween: Tween(begin: score.toDouble(), end: score.toDouble()),
          duration: AppMotion.base,
          builder: (context, v, _) =>
              Text('${v.round()}', style: theme.textTheme.labelLarge),
        ),
      ),
    );
  }
}

/// Friendly empty state — no tasks yet.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text('Nothing to prove yet',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add a task — it only counts once the evidence checks out.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
