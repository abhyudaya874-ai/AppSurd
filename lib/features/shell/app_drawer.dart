import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/transitions.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../arena/arena_state.dart';
import '../profile/profile_data.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import 'app_shell.dart';

/// Search text submitted from the sidebar — the Tasks destination picks it
/// up as its initial filter (opens the search field pre-filled).
final tasksSearchProvider = NotifierProvider<TasksSearchNotifier, String>(
  TasksSearchNotifier.new,
);

class TasksSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Sets the pending search text; Tasks consumes it on next build.
  void set(String v) => state = v;
}

/// The ChatGPT-app-style sidebar: search field, nav rows (active = soft
/// accent pill), "Recent" tasks, and a pinned account footer (profile +
/// settings gear). Rows stagger in via FadeSlideIn on first open.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({
    super.key,
    required this.width,
    required this.pageCount,
    required this.onNavigate,
    required this.onClose,
  });

  final double width;
  final int pageCount;
  final ValueChanged<int> onNavigate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final index = ref.watch(navIndexProvider);
    final arenaReady = ref.watch(arenaReadyProvider);
    final profile = ref.watch(profileProvider);
    final integrity = ref.watch(integrityScoreProvider);
    final tasks = ref.watch(tasksProvider).value ?? const [];

    final items = <(IconData, String, int)>[
      (Icons.home_rounded, 'Home', 0),
      (Icons.checklist_rounded, 'Tasks', 1),
      (Icons.calendar_month_rounded, 'Schedule', 2),
      (Icons.chat_bubble_outline_rounded, 'Ask', 3),
      (Icons.person_outline_rounded, 'Profile', 4),
      if (arenaReady) (Icons.groups_rounded, 'Arena', 5),
    ];

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xs),
            // ---- Brand row ----
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    'Receipts',
                    style: AppTypography.grotesk(theme.colorScheme.onSurface)
                        .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close menu',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),

            // ---- Search (filters recents; submit → Tasks pre-filtered) ----
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 4,
              ),
              child: _SearchField(
                onSubmitted: (q) {
                  ref.read(tasksSearchProvider.notifier).set(q);
                  onNavigate(1);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // ---- Nav rows ----
            for (var i = 0; i < items.length; i++)
              FadeSlideIn(
                index: i,
                stagger: const Duration(milliseconds: 30),
                child: _NavRow(
                  icon: items[i].$1,
                  label: items[i].$2,
                  active: index == items[i].$3,
                  onTap: () => onNavigate(items[i].$3),
                ),
              ),

            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recent',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            // ---- Recent tasks (status dot + one-line title) ----
            Expanded(
              child: _RecentList(tasks: tasks, onClose: onClose),
            ),

            // ---- Footer: account + settings ----
            Divider(height: 1, color: theme.colorScheme.outline),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onNavigate(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              backgroundImage: profile.avatarPath != null
                                  ? FileImage(File(profile.avatarPath!))
                                  : null,
                              child: profile.avatarPath == null
                                  ? Text(
                                      profile.initials,
                                      style: theme.textTheme.labelMedium,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                profile.name.isEmpty
                                    ? 'Set your name'
                                    : profile.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              '$integrity',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).push(AppTransitions.sharedAxis(const SettingsScreen()));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded search field; live-filters the Recent list via a local query —
/// submission forwards the query to the Tasks destination.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField({required this.onSubmitted});
  final ValueChanged<String> onSubmitted;

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _ctrl,
      onChanged: (_) => ref.read(tasksSearchProvider.notifier).set(_ctrl.text),
      onSubmitted: widget.onSubmitted,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search tasks',
        isDense: true,
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 10,
        ),
      ),
    );
  }
}

/// One nav row — active gets a soft accent pill behind icon + label.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1,
      ),
      child: Semantics(
        label: 'Navigate to $label',
        selected: active,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: active ? color : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Last ~8 tasks with status dots; the sidebar search filters this live.
class _RecentList extends ConsumerWidget {
  const _RecentList({required this.tasks, required this.onClose});
  final List<Task> tasks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final q = ref.watch(tasksSearchProvider).trim().toLowerCase();
    final recent = tasks
        .where((t) => q.isEmpty || t.title.toLowerCase().contains(q))
        .take(8)
        .toList();
    if (recent.isEmpty) {
      return Center(
        child: Text(
          q.isEmpty ? 'No tasks yet' : 'No matches',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      itemCount: recent.length,
      itemBuilder: (context, i) {
        final t = recent[i];
        final dot = switch (t.status) {
          TaskStatus.done => theme.colorScheme.primary,
          TaskStatus.verifying => theme.colorScheme.primary,
          TaskStatus.locked => theme.colorScheme.tertiary,
          TaskStatus.open => theme.colorScheme.onSurfaceVariant,
        };
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          title: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          onTap: () {
            onClose();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TaskDetailScreen(taskId: t.id),
              ),
            );
          },
        );
      },
    );
  }
}
