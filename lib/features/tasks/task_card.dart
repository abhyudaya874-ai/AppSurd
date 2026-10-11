import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/pressable.dart';
import 'task_model.dart';

/// One task in the list. The card container + title carry the Hero tag into
/// the detail screen; the status chip mirrors the task state machine.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

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
              AnimatedDefaultTextStyle(
                duration: AppMotion.fast,
                style: theme.textTheme.labelSmall!.copyWith(color: color),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
