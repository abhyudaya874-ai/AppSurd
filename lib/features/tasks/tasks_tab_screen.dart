import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../shell/app_drawer.dart';
import '../shell/app_shell.dart';
import 'focus_view.dart';
import 'group_model.dart';
import 'task_model.dart';
import 'task_row.dart';
import 'task_view_options.dart';
import 'tasks_provider.dart';

/// Tasks tab — the full list moved out of Home. Header carries search, the
/// List|Focus toggle and the group/sort popover; beneath it a "stories" row
/// of group avatars that collapses into an overlapped cluster beside the
/// title on scroll. Sections/rows honour persisted group-by + sort-by.
class TasksTabScreen extends ConsumerStatefulWidget {
  const TasksTabScreen({super.key});

  @override
  ConsumerState<TasksTabScreen> createState() => _TasksTabScreenState();
}

class _TasksTabScreenState extends ConsumerState<TasksTabScreen> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _searchOpen = false;
  bool _focusMode = false;
  TaskStatus? _statusFilter;
  String? _groupFilter; // '' = Inbox, null = all

  /// Section/index pairs already entrance-animated — rows only animate on
  /// first build, never on every scroll.
  final _seenSections = <String>{};

  static const _avatarRowH = 84.0;
  static const _headerMax = 158.0;
  static const _headerMin = 56.0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(tasksProvider);
    final groups = ref.watch(groupsProvider);
    final view = ref.watch(taskViewProvider);
    final now = DateTime.now();

    // Clear the "freshly created" highlight after the pulse has played.
    if (ref.read(highlightedTaskProvider) != null) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          ref.read(highlightedTaskProvider.notifier).set(null);
        }
      });
    }

    // Consume any search submitted from the sidebar — opens the field
    // pre-filtered.
    final seed = ref.watch(tasksSearchProvider);
    if (seed.isNotEmpty && !_searchOpen) {
      _searchCtrl.text = seed;
      _searchOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(tasksSearchProvider.notifier).set('');
      });
    }

    final bottomPad = 24.0 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          // Snap the collapsing header to whichever end is closer — it must
          // never rest mid-fold.
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              const range = _headerMax - _headerMin;
              final off = _scroll.offset;
              if (_scroll.hasClients && off > 0 && off < range) {
                _scroll.animateTo(
                  off < range / 2 ? 0 : range,
                  duration: AppMotion.of(context, AppMotion.base),
                  curve: AppMotion.standard,
                );
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                // ---- Collapsing header: title row + stories avatars ----
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StoriesHeaderDelegate(
                    minExtent: _headerMin,
                    maxExtent: _headerMax,
                    avatarRowHeight: _avatarRowH,
                    builder: (context, t) => _header(
                      context,
                      theme,
                      groups,
                      tasksAsync.value ?? const [],
                      t,
                    ),
                  ),
                ),

                // ---- Collapsing search field ----
                SliverToBoxAdapter(
                  child: AnimatedSize(
                    duration: AppMotion.of(context, AppMotion.base),
                    curve: AppMotion.standard,
                    child: _searchOpen
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search tasks',
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, size: 18),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => setState(() {
                                    _searchOpen = false;
                                    _searchCtrl.clear();
                                  }),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),

                // ---- Status filter chips ----
                SliverToBoxAdapter(child: _filterBar(theme)),

                // ---- Content: states / Focus feed / sticky sections ----
                ..._contentSlivers(
                  theme,
                  tasksAsync,
                  groups,
                  view,
                  now,
                  bottomPad,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The list region: loading/error/empty, the Focus snap feed, or one
  /// [SliverMainAxisGroup] per section whose pinned header sticks under the
  /// collapsing header until that section's last row scrolls past — then
  /// the next section's header pushes it out (built-in behaviour).
  List<Widget> _contentSlivers(
    ThemeData theme,
    AsyncValue<List<Task>> tasksAsync,
    List<Group> groups,
    TaskViewOptions view,
    DateTime now,
    double bottomPad,
  ) {
    return tasksAsync.when(
      loading: () => [
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (e, _) => [
        const SliverFillRemaining(
          child: Center(child: Text('Could not load tasks.')),
        ),
      ],
      data: (tasks) {
        final list = _filtered(tasks, now);
        if (list.isEmpty) {
          return [
            SliverFillRemaining(child: _EmptyState(filtered: tasks.isNotEmpty)),
          ];
        }
        if (_focusMode) {
          return [
            SliverFillRemaining(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPad - 60),
                child: FocusTaskFeed(tasks: list),
              ),
            ),
          ];
        }
        final sections = groupTasks(list, groups, view.groupBy, now);
        return [
          for (final s in sections)
            SliverMainAxisGroup(
              slivers: [
                if (s.label.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(
                      label: s.label,
                      count: s.tasks.length,
                    ),
                  ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    for (var i = 0; i < s.tasks.length; i++)
                      // Entrance-animate only the first time a row is
                      // built — never on every scroll.
                      _seenSections.add('${s.label}#$i')
                          ? FadeSlideIn(
                              index: i,
                              stagger: const Duration(milliseconds: 40),
                              child: _rowPad(s.tasks[i]),
                            )
                          : _rowPad(s.tasks[i]),
                  ]),
                ),
              ],
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
        ];
      },
    );
  }

  /// Row padding wrapper shared by the animated/static paths above.
  Widget _rowPad(Task task) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xxs,
    ),
    child: TaskRow(task: task),
  );

  /// Header content rendered inside the persistent sliver. [t] is collapse
  /// progress 0→1 and drives EVERYTHING directly — no setState, no implicit
  /// animations: the stories row tilts back in perspective, translates up,
  /// shrinks and fades; the title shrinks 28→18; the avatar cluster docks
  /// beside the title once t > 0.6.
  Widget _header(
    BuildContext context,
    ThemeData theme,
    List<Group> groups,
    List<Task> all,
    double t,
  ) {
    final avatarT = (1 - (t / 0.75)).clamp(0.0, 1.0); // gone by 75%
    final clusterT = ((t - 0.6) / 0.4).clamp(0.0, 1.0); // docks after 60%
    final titleT = Curves.easeOut.transform(t);
    final titleSize = 28 - 10 * titleT; // 28sp → 18sp
    final storyGroups = _storyGroups(groups, all);

    return RepaintBoundary(
      child: Stack(
        children: [
          // Title row (always visible, shrinks on collapse).
          Positioned(
            top: 6,
            left: AppSpacing.lg,
            right: AppSpacing.xs,
            child: Row(
              children: [
                const MenuAvatar(size: 30),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Tasks',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: titleSize,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Overlapped avatar cluster docked beside the title.
                Expanded(
                  child: Opacity(
                    opacity: clusterT,
                    child: _AvatarCluster(
                      groups: storyGroups,
                      all: all,
                      onPick: _pickGroupFilter,
                    ),
                  ),
                ),
                _segToggle(theme),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _searchCtrl.clear();
                  }),
                ),
                IconButton(
                  tooltip: 'Group & sort',
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  onPressed: _openViewMenu,
                ),
              ],
            ),
          ),
          // Stories row — folds away in perspective (tilt + shrink + fade).
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            height: _avatarRowH,
            child: Opacity(
              opacity: avatarT,
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(t * 0.9),
                child: Transform.translate(
                  offset: Offset(0, -24 * t),
                  child: Transform.scale(
                    scale: 1 - 0.45 * t, // 1.0 → 0.55
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      ignoring: avatarT < 0.2,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _GroupAvatar(
                            label: 'All',
                            count: all.length,
                            color: theme.colorScheme.primary,
                            selected: _groupFilter == null,
                            onTap: () => _pickGroupFilter(null),
                          ),
                          for (final g in storyGroups)
                            _GroupAvatar(
                              label: g.name,
                              count: all.where((t) => t.groupId == g.id).length,
                              color: g.color,
                              selected: _groupFilter == g.id,
                              onTap: () => _pickGroupFilter(g.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Groups that have ≥1 task — just the real groups; no synthetic Inbox
  /// avatar (users read "All" as the unfiltered state).
  List<Group> _storyGroups(List<Group> groups, List<Task> all) {
    return [
      for (final g in groups)
        if (all.any((t) => t.groupId == g.id)) g,
    ];
  }

  bool _isInbox(Task t, List<Group> groups) =>
      t.groupId == null || !groups.any((g) => g.id == t.groupId);

  void _pickGroupFilter(String? id) {
    HapticFeedback.selectionClick();
    setState(() => _groupFilter = id);
  }

  /// Compact List|Focus segmented toggle in the header.
  Widget _segToggle(ThemeData theme) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            theme,
            Icons.view_list_rounded,
            !_focusMode,
            () => setState(() => _focusMode = false),
            'List view',
          ),
          _seg(
            theme,
            Icons.view_carousel_rounded,
            _focusMode,
            () => setState(() => _focusMode = true),
            'Focus view',
          ),
        ],
      ),
    );
  }

  Widget _seg(
    ThemeData theme,
    IconData icon,
    bool on,
    VoidCallback tap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          tap();
        },
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          width: 40,
          height: 30,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: on
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 17,
            color: on
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Status filter chips: All · Open · Verifying · Locked · Verified · Clear.
  Widget _filterBar(ThemeData theme) {
    final opts = <(TaskStatus?, String)>[
      (null, 'All'),
      (TaskStatus.open, 'Open'),
      (TaskStatus.verifying, 'Verifying'),
      (TaskStatus.locked, 'Locked'),
      (TaskStatus.done, 'Verified'),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const SizedBox(width: AppSpacing.md),
          for (final (v, label) in opts)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 8),
              child: AppChip(
                label: label,
                filled: _statusFilter == v,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _statusFilter = v);
                },
              ),
            ),
          if (_groupFilter != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppChip(
                label: 'Group ✕',
                onTap: () => setState(() => _groupFilter = null),
              ),
            ),
        ],
      ),
    );
  }

  /// Applies status filter + avatar-group filter + search text, then the
  /// persisted sort. Grouping happens at render time per section.
  List<Task> _filtered(List<Task> tasks, DateTime now) {
    final groups = ref.read(groupsProvider);
    var list = tasks;
    if (_statusFilter != null) {
      list = list.where((t) => t.status == _statusFilter).toList();
    }
    if (_groupFilter != null) {
      list = _groupFilter!.isEmpty
          ? list.where((t) => _isInbox(t, groups)).toList()
          : list.where((t) => t.groupId == _groupFilter).toList();
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (t) =>
                t.title.toLowerCase().contains(q) ||
                t.description.toLowerCase().contains(q),
          )
          .toList();
    }
    final view = ref.read(taskViewProvider);
    return sortTasks(list, view.sortBy, view.ascending);
  }

  /// Two-stage anchored popover: main rows (Group by / Sort by / direction)
  /// → tapping a row swaps the card to a checkmark list with a back button.
  void _openViewMenu() {
    HapticFeedback.selectionClick();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: AppMotion.fast,
      pageBuilder: (context, anim, secondary) => SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 100, right: AppSpacing.md),
            child: FadeTransition(opacity: anim, child: const _ViewMenuCard()),
          ),
        ),
      ),
    );
  }
}

/// The popover card — two stages driven by a local page enum so the content
/// swaps in place with a size-aware cross-fade (ref: recording 1).
class _ViewMenuCard extends ConsumerStatefulWidget {
  const _ViewMenuCard();

  @override
  ConsumerState<_ViewMenuCard> createState() => _ViewMenuCardState();
}

enum _Stage { main, groupBy, sortBy }

class _ViewMenuCardState extends ConsumerState<_ViewMenuCard> {
  _Stage _stage = _Stage.main;

  static const _groupLabels = {
    TaskGroupBy.none: 'None',
    TaskGroupBy.status: 'Status',
    TaskGroupBy.group: 'Group',
    TaskGroupBy.due: 'Due date',
    TaskGroupBy.priority: 'Priority',
  };
  static const _sortLabels = {
    TaskSortBy.created: 'Created',
    TaskSortBy.due: 'Due date',
    TaskSortBy.title: 'Title',
    TaskSortBy.activity: 'Last activity',
    TaskSortBy.priority: 'Priority',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = ref.watch(taskViewProvider);
    final set = ref.read(taskViewProvider.notifier).set;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: AnimatedSize(
          duration: AppMotion.of(context, AppMotion.base),
          curve: AppMotion.standard,
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.fast),
            child: switch (_stage) {
              _Stage.main => _mainStage(theme, view),
              _Stage.groupBy => _pickStage(
                theme,
                'Group by',
                _groupLabels,
                view.groupBy,
                (g) => set(view.copyWith(groupBy: g)),
              ),
              _Stage.sortBy => _pickStage(
                theme,
                'Sort by',
                _sortLabels,
                view.sortBy,
                (s) => set(view.copyWith(sortBy: s)),
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _mainStage(ThemeData theme, TaskViewOptions view) {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(
          theme,
          'Group by',
          _groupLabels[view.groupBy]!,
          () => setState(() => _stage = _Stage.groupBy),
        ),
        Divider(height: 1, color: theme.colorScheme.outline),
        _row(
          theme,
          'Sort by',
          _sortLabels[view.sortBy]!,
          () => setState(() => _stage = _Stage.sortBy),
        ),
        Divider(height: 1, color: theme.colorScheme.outline),
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            ref
                .read(taskViewProvider.notifier)
                .set(view.copyWith(ascending: !view.ascending));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Direction', style: theme.textTheme.bodyMedium),
                ),
                Icon(
                  view.ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  view.ascending ? 'Ascending' : 'Descending',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// The checkmark list stage with a back affordance.
  Widget _pickStage<T>(
    ThemeData theme,
    String title,
    Map<T, String> labels,
    T current,
    ValueChanged<T> onPick,
  ) {
    return Column(
      key: ValueKey(title),
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _stage = _Stage.main),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outline),
        for (final e in labels.entries)
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onPick(e.key);
              setState(() => _stage = _Stage.main);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(e.value, style: theme.textTheme.bodyMedium),
                  ),
                  if (e.key == current)
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Overlapped avatar cluster shown beside the title when the stories row
/// collapses (ref: recording 2). Tapping opens the same group filter.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({
    required this.groups,
    required this.all,
    required this.onPick,
  });
  final List<Group> groups;
  final List<Task> all;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    const size = 26.0, overlap = 9.0;
    final theme = Theme.of(context);
    final items = groups.take(4).toList();
    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width:
                size + (items.isEmpty ? 0 : (items.length) * (size - overlap)),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: _mini(
                    theme.colorScheme.primary,
                    '≡',
                    () => onPick(null),
                  ),
                ),
                for (var i = 0; i < items.length; i++)
                  Positioned(
                    left: size - overlap + i * (size - overlap),
                    child: _mini(
                      items[i].color,
                      items[i].name.isEmpty ? '?' : items[i].name[0],
                      () => onPick(items[i].id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mini(Color color, String letter, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1D22),
          border: Border.all(color: color, width: 1.6),
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// One circular "story" avatar: colour ring, initial, count badge.
class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.base),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface,
                    border: Border.all(
                      color: selected ? color : color.withValues(alpha: 0.45),
                      width: selected ? 2.4 : 1.6,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label.isEmpty ? '?' : label[0].toUpperCase(),
                    style: theme.textTheme.titleMedium?.copyWith(color: color),
                  ),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned section header ("Today · 4") — sticks under the collapsing
/// header until its section's last row scrolls past, then the next
/// section's header pushes it out (SliverMainAxisGroup behaviour). Solid
/// background so rows slide under it cleanly; a hairline appears only
/// while content is overlapping it.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({required this.label, required this.count});

  final String label;
  final int count;

  @override
  double get minExtent => 30;
  @override
  double get maxExtent => 30;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent
                ? theme.colorScheme.outline
                : Colors.transparent,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate old) =>
      old.label != label || old.count != count;
}

/// Persistent-header plumbing: hands collapse progress (0→1) to [builder].
class _StoriesHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StoriesHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.avatarRowHeight,
    required this.builder,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final double avatarRowHeight;
  final Widget Function(BuildContext context, double t) builder;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    // Opaque backdrop once collapsed so rows don't show through.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor
          .withValues(alpha: t.clamp(0.0, 1.0)),
      child: builder(context, t),
    );
  }

  @override
  bool shouldRebuild(_StoriesHeaderDelegate old) => true;
}

/// Receipt empty state (kept from the old Home, moved here with the list).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedAppIcon(
            type: AppIconType.receipt,
            active: true,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            filtered ? 'Nothing in this filter' : 'Nothing to prove yet',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            filtered ? 'Try clearing filters or search.' : 'Add a task from Home — it only counts once evidence checks out.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
