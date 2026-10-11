import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/transitions.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../profile/profile_data.dart';
import '../settings/settings_screen.dart';
import '../tasks/group_model.dart';
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
    final profile = ref.watch(profileProvider);
    final integrity = ref.watch(integrityScoreProvider);
    final tasks = ref.watch(tasksProvider).value ?? const [];

    final items = <(IconData, String, int)>[
      (Icons.home_rounded, 'Home', 0),
      (Icons.checklist_rounded, 'Tasks', 1),
      (Icons.calendar_month_rounded, 'Schedule', 2),
      (Icons.chat_bubble_outline_rounded, 'Ask', 3),
      (Icons.person_outline_rounded, 'Profile', 4),
      (Icons.groups_rounded, 'Arena', 5),
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

/// Last ~8 tasks with status dots; the sidebar search filters this live./// Last ~8 tasks with status dots; the sidebar search filters this live.
/// Pinned tasks float to the top. Long-press (or the ⋮ button) opens an
/// animated context menu — Pin, Mark unread, Rename, Move to group, Delete.
class _RecentList extends ConsumerWidget {
  const _RecentList({required this.tasks, required this.onClose});
  final List<Task> tasks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final q = ref.watch(tasksSearchProvider).trim().toLowerCase();
    final recent =
        tasks
            .where((t) => q.isEmpty || t.title.toLowerCase().contains(q))
            .toList()
          // Pinned first, then provider order (created desc).
          ..sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
    final shown = recent.take(8).toList();
    if (shown.isEmpty) {
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
      itemCount: shown.length,
      itemBuilder: (context, i) => _RecentRow(task: shown[i], onClose: onClose),
    );
  }
}

/// One recent-task row with a ChatGPT-style long-press context menu.
class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.task, required this.onClose});
  final Task task;
  final VoidCallback onClose;

  /// Rename → dialog → updateTask (write-through to Hive as usual).
  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: task.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename task'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Task title'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref
          .read(tasksProvider.notifier)
          .updateTask(task.copyWith(title: name));
    }
  }

  /// Delete with the same undo snackbar the Tasks list uses.
  void _delete(BuildContext context, WidgetRef ref) {
    final n = ref.read(tasksProvider.notifier);
    n.deleteTask(task.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${task.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => n.restoreTask(task),
        ),
      ),
    );
  }

  /// Move-to-group submenu entries: each group + "No group".
  List<Widget> _groupItems(WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    return [
      for (final g in groups)
        MenuItemButton(
          leadingIcon: Icon(Icons.circle, size: 10, color: g.color),
          onPressed: () => ref
              .read(tasksProvider.notifier)
              .updateTask(task.copyWith(groupId: g.id)),
          child: Text(g.name),
        ),
      if (groups.isNotEmpty) const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.remove_circle_outline, size: 16),
        onPressed: () => ref
            .read(tasksProvider.notifier)
            .updateTask(task.copyWith(clearGroupId: true)),
        child: const Text('No group'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = task;
    final dot = t.unread
        ? theme
              .colorScheme
              .primary // unread overrides the status dot
        : switch (t.status) {
            TaskStatus.done => theme.colorScheme.primary,
            TaskStatus.verifying => theme.colorScheme.primary,
            TaskStatus.locked => theme.colorScheme.tertiary,
            TaskStatus.open => theme.colorScheme.onSurfaceVariant,
          };

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          theme.colorScheme.surfaceContainerHighest,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      builder: (context, controller, child) => ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        title: Row(
          children: [
            if (t.pinned)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.push_pin_rounded,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            Expanded(
              child: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert_rounded, size: 16),
          visualDensity: VisualDensity.compact,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
        onTap: () {
          // Opening a recent marks it read, then navigates to detail.
          if (t.unread) {
            ref
                .read(tasksProvider.notifier)
                .updateTask(t.copyWith(unread: false));
          }
          onClose();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TaskDetailScreen(taskId: t.id),
            ),
          );
        },
        onLongPress: () => controller.open(),
      ),
      menuChildren: [
        _item(
          theme,
          icon: t.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: t.pinned ? 'Unpin' : 'Pin',
          shortcut: 'P',
          onTap: () => ref
              .read(tasksProvider.notifier)
              .updateTask(t.copyWith(pinned: !t.pinned)),
        ),
        _item(
          theme,
          icon: t.unread
              ? Icons.mark_email_read_outlined
              : Icons.mark_email_unread_outlined,
          label: t.unread ? 'Mark as read' : 'Mark as unread',
          shortcut: 'U',
          onTap: () => ref
              .read(tasksProvider.notifier)
              .updateTask(t.copyWith(unread: !t.unread)),
        ),
        _item(
          theme,
          icon: Icons.edit_outlined,
          label: 'Rename',
          shortcut: 'R',
          onTap: () => _rename(context, ref),
        ),
        SubmenuButton(
          leadingIcon: Icon(
            Icons.folder_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          menuChildren: _groupItems(ref),
          child: _row(theme, 'Move to group', '›'),
        ),
        const Divider(height: 1),
        _item(
          theme,
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          shortcut: 'D',
          danger: true,
          onTap: () => _delete(context, ref),
        ),
      ],
    );
  }

  /// One menu row: icon + label + trailing shortcut letter (ChatGPT style).
  Widget _item(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String shortcut,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return MenuItemButton(
      leadingIcon: Icon(
        icon,
        size: 16,
        color: danger
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
      onPressed: onTap,
      child: _row(
        theme,
        label,
        shortcut,
        color: danger ? theme.colorScheme.error : null,
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String shortcut, {Color? color}) {
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
          const Spacer(),
          Text(
            shortcut,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
