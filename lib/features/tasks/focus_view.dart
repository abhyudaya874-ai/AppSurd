import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import 'evidence_sheet.dart';
import 'group_model.dart';
import 'task_detail_screen.dart';
import 'task_model.dart';
import 'task_view_options.dart';

/// "Focus" mode — a reels-style vertical card feed: the centred card is full
/// size/opacity, neighbours shrink to ~90% and dim to ~55% while peeking in
/// from above/below. One page = one task.
class FocusTaskFeed extends ConsumerStatefulWidget {
  const FocusTaskFeed({super.key, required this.tasks});

  /// Flattened, already sorted+filtered list (sections don't apply here).
  final List<Task> tasks;

  @override
  ConsumerState<FocusTaskFeed> createState() => _FocusTaskFeedState();
}

class _FocusTaskFeedState extends ConsumerState<FocusTaskFeed> {
  late final PageController _page;

  @override
  void initState() {
    super.initState();
    _page = PageController(viewportFraction: 0.80);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _page,
      scrollDirection: Axis.vertical,
      pageSnapping: true,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.tasks.length,
      onPageChanged: (_) => HapticFeedback.selectionClick(),
      itemBuilder: (context, i) => AnimatedBuilder(
        animation: _page,
        builder: (context, child) {
          // Distance from the centred page → scale/opacity. Before the first
          // layout `page` is null; fall back to the integer index.
          final p = _page.hasClients ? (_page.page ?? 0) : 0.0;
          final d = (p - i).abs().clamp(0.0, 1.0);
          final scale = 1.0 - d * 0.10;
          final opacity = 1.0 - d * 0.45;
          return Transform.scale(
            scale: scale,
            child: Opacity(opacity: opacity, child: child),
          );
        },
        child: _FocusCard(task: widget.tasks[i]),
      ),
    );
  }
}

/// A single focus card — bigger than a list row: group, due chip, proof
/// requirement, attempts, and the "Prove it" call-to-action.
class _FocusCard extends ConsumerWidget {
  const _FocusCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = task;
    final group = ref
        .watch(groupsProvider)
        .where((g) => g.id == t.groupId)
        .firstOrNull;
    final statusLabel = switch (t.status) {
      TaskStatus.open => 'needs proof',
      TaskStatus.verifying => 'verifying…',
      TaskStatus.locked => 'challenge pending',
      TaskStatus.done => 'verified ✓',
    };
    final statusColor = switch (t.status) {
      TaskStatus.done || TaskStatus.verifying => theme.colorScheme.primary,
      TaskStatus.locked => theme.colorScheme.tertiary,
      TaskStatus.open => theme.colorScheme.onSurfaceVariant,
    };

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: group?.color ?? theme.colorScheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  group?.name ?? 'Inbox',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (t.dueAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Text(
                      'due ${dueBucket(t.dueAt, DateTime.now())}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              t.title,
              style: theme.textTheme.headlineMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (t.description.isNotEmpty)
              Text(
                'Proof: ${t.description}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${t.attempts.length} attempt${t.attempts.length == 1 ? '' : 's'}'
              ' · $statusLabel',
              style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => EvidenceSheet.show(context, t),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Prove it'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TaskDetailScreen(taskId: t.id),
                    ),
                  ),
                  child: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
