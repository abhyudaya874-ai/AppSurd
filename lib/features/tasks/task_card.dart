import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/drawn_check.dart';
import '../../core/widgets/pressable.dart';
import 'task_model.dart';

/// One task in the list. The card container + title carry the Hero tag into
/// the detail screen; the status chip mirrors the task state machine.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    this.accountabilityPending = false,
  });

  final Task task;
  final VoidCallback onTap;

  /// Shows the "unresolved accountability" dot when another task is locked.
  final bool accountabilityPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (task.status) {
      TaskStatus.open => ('needs proof', theme.colorScheme.onSurfaceVariant),
      TaskStatus.verifying => ('verifying…', theme.colorScheme.primary),
      TaskStatus.locked => ('challenge pending', theme.colorScheme.tertiary),
      TaskStatus.done => ('verified', theme.colorScheme.primary),
    };
    return Pressable(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Hero(
                          tag: 'task-title-${task.id}',
                          child: Material(
                            type: MaterialType.transparency,
                            child: Text(
                              task.title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      if (task.isDemo)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text('demo',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.tertiary)),
                        ),
                      if (accountabilityPending)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Tooltip(
                            message: 'Unresolved accountability on another task',
                            child: Icon(Icons.flag_outlined,
                                size: 14,
                                color: theme.colorScheme.tertiary),
                          ),
                        ),
                    ]),
                    if (task.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          task.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (task.status == TaskStatus.done) ...[
                  DrawnCheck(size: 12, color: color, strokeWidth: 2),
                  const SizedBox(width: 3),
                ],
                AnimatedDefaultTextStyle(
                  duration: AppMotion.fast,
                  style: theme.textTheme.labelSmall!.copyWith(color: color),
                  child: Text(label),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
