import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../../core/widgets/pressable.dart';
import '../../core/utils/responsive.dart';
import '../model_picker/model_pill.dart';
import '../model_picker/model_selection.dart';
import '../model_picker/resolved_model.dart';
import '../voice/voice_overlay.dart';
import 'evidence_sheet.dart';
import 'group_model.dart';
import 'task_card.dart';
import 'task_detail_screen.dart';
import 'task_model.dart';
import 'tasks_provider.dart';

/// Home (Tasks tab) — Perplexity-style: teal section label + serif headline,
/// a composer card (field + chips + round send), suggestion chips, then
/// grouped, filterable task rows. No FAB; the tab bar owns navigation.
class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final _ctrl = TextEditingController();
  String? _filter; // null = All; status name or 'g:<id>' for groups

  static const _suggestions = [
    'Finish an assignment',
    'Push a commit',
    'Read 20 pages',
    'Gym session',
  ];

  Future<void> _submit() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty) return;
    _ctrl.clear();
    FocusScope.of(context).unfocus();
    await ref.read(tasksProvider.notifier).addTask(title: title);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(tasksProvider);
    final groups = ref.watch(groupsProvider);
    final arenaOn =
        ref.watch(modelSelectionProvider.select((s) => s.arenaMode));

    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: CustomScrollView(slivers: [
            // ---- Header: mark + integrity chip ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Row(children: [
                  const AnimatedAppIcon(
                      type: AppIconType.receipt, active: true, size: 22),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Receipts',
                      style: AppTypography.grotesk(
                              theme.colorScheme.onSurface)
                          .copyWith(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const _IntegrityChip(),
                ]),
              ),
            ),

            // ---- Label + serif headline ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                child: FadeSlideIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TASKS',
                          style: AppTypography.sectionLabel(
                              theme.colorScheme.primary)),
                      const SizedBox(height: 4),
                      Text('What will you prove today?',
                          style: AppTypography.display(
                              theme.colorScheme.onSurface,
                              size: 32)),
                    ],
                  ),
                ),
              ),
            ),

            // ---- Composer card ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _Composer(
                  ctrl: _ctrl,
                  arenaOn: arenaOn,
                  onSubmit: _submit,
                ),
              ),
            ),

            // ---- Suggestion chips ----
            SliverToBoxAdapter(
              child: SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  children: [
                    for (var i = 0; i < _suggestions.length; i++)
                      FadeSlideIn(
                        index: i,
                        stagger: const Duration(milliseconds: 60),
                        child: Padding(
                          padding:
                              const EdgeInsets.only(right: AppSpacing.xs),
                          child: _Chip(
                            label: _suggestions[i],
                            onTap: () {
                              _ctrl.text = _suggestions[i];
                              _ctrl.selection = TextSelection.collapsed(
                                  offset: _ctrl.text.length);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ---- Filter chips ----
            SliverToBoxAdapter(
              child: _FilterBar(
                filter: _filter,
                groups: groups,
                onPick: (f) => setState(() => _filter = f),
              ),
            ),

            // ---- Task list ----
            tasksAsync.when(
              loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SliverFillRemaining(
                  child: Center(child: Text('Could not load tasks.'))),
              data: (tasks) {
                final filtered = _applyFilter(tasks, groups);
                if (filtered.isEmpty && _filter == null) {
                  return const SliverFillRemaining(child: _EmptyState());
                }
                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                      child: Center(
                          child: Text('Nothing in this filter.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant))));
                }
                // Group sections (ungrouped first), each collapsible.
                final grouped = <Group?, List<Task>>{null: []};
                for (final t in filtered) {
                  grouped.putIfAbsent(
                      groups.where((g) => g.id == t.groupId).firstOrNull,
                      () => []).add(t);
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    for (final entry in grouped.entries)
                      if (entry.value.isNotEmpty)
                        _GroupSection(
                          group: entry.key,
                          tasks: entry.value,
                          collapsedInitially: false,
                        ),
                    const SizedBox(height: 110), // tab-bar clearance
                  ]),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  List<Task> _applyFilter(List<Task> tasks, List<Group> groups) {
    if (_filter == null) return tasks;
    if (_filter!.startsWith('g:')) {
      return tasks.where((t) => t.groupId == _filter!.substring(2)).toList();
    }
    final want = TaskStatus.values.firstWhere((s) => s.name == _filter);
    return tasks.where((t) => t.status == want).toList();
  }
}

/// Small pill chip used for suggestions, filters, and composer chips.
class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, this.onTap, this.filled = false, this.trailing});
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: filled
          ? theme.colorScheme.primary.withValues(alpha: 0.18)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: filled
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outline,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: filled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant)),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

/// The composer card — task field + chip row + round send button.
class _Composer extends ConsumerStatefulWidget {
  const _Composer(
      {required this.ctrl, required this.arenaOn, required this.onSubmit});

  final TextEditingController ctrl;
  final bool arenaOn;
  final VoidCallback onSubmit;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  String? _groupId; // null = Inbox

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints =
        theme.extension<ProviderTints>() ?? const ProviderTints();
    final tint = ref.watch(resolvedModelProvider) != null
        ? tints.forId(ref.watch(resolvedModelProvider)!.provider.id)
        : theme.colorScheme.primary;
    final groups = ref.watch(groupsProvider);
    final group =
        groups.where((g) => g.id == _groupId).firstOrNull;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: Column(children: [
        TextField(
          controller: widget.ctrl,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => widget.onSubmit(),
          decoration: InputDecoration(
            hintText: 'Add a task…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(children: [
          // Group chip — assign the task to a group, or make a new one.
          _Chip(
            label: group?.name ?? 'Inbox',
            trailing: Icon(Icons.expand_more,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            onTap: () => _pickGroup(groups),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Flexible(child: ModelPill()),
          VoiceOrbButton(
            intent: VoiceIntent.task,
            onResult: (r) {
              widget.ctrl.text = r.text;
              widget.ctrl.selection =
                  TextSelection.collapsed(offset: r.text.length);
            },
          ),
          const SizedBox(width: AppSpacing.xs),
          // Round white send — the composer pattern's signature.
          Pressable(
            onTap: _submit,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.onSurface,
                border:
                    Border.all(color: tint.withValues(alpha: 0.6)),
              ),
              child: Icon(Icons.arrow_upward_rounded,
                  color: theme.colorScheme.surface, size: 20),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _submit() async {
    final title = widget.ctrl.text.trim();
    if (title.isEmpty) return;
    widget.ctrl.clear();
    FocusScope.of(context).unfocus();
    await ref
        .read(tasksProvider.notifier)
        .addTask(title: title, groupId: _groupId);
  }

  /// Bottom-sheet group picker with a "new group" tile + color picker.
  Future<void> _pickGroup(List<Group> groups) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.inbox_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: const Text('Inbox'),
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final g in groups)
            ListTile(
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: g.color, shape: BoxShape.circle),
              ),
              title: Text(g.name),
              onTap: () => Navigator.pop(context, g.id),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New group'),
            onTap: () => Navigator.pop(context, 'new'),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    if (picked == 'new') {
      final g = await _newGroupSheet();
      if (g != null) setState(() => _groupId = g.id);
      return;
    }
    setState(() => _groupId = picked.isEmpty ? null : picked);
  }

  /// Name + color picker; returns the created group.
  Future<Group?> _newGroupSheet() async {
    final ctrl = TextEditingController();
    const palette = [
      Color(0xFF4FD8E0), Color(0xFFFBBF24), Color(0xFFB794F6),
      Color(0xFF4ADE80), Color(0xFFFF6B6B), Color(0xFF60A5FA),
    ];
    Color picked = palette[0];
    final ok = await showModalBottomSheet<Group>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 8,
              bottom:
                  MediaQuery.viewInsetsOf(context).bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('New group',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'Group name'),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              for (final c in palette)
                GestureDetector(
                  onTap: () => set(() => picked = c),
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: picked == c
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context,
                    Group(id: 'custom', name: name, color: picked));
              },
              child: const Text('Create'),
            ),
          ]),
        ),
      ),
    );
    return ok;
  }
}

/// Filter chips row: All · Open · Locked · Verified · one per group · Clear.
class _FilterBar extends StatelessWidget {
  const _FilterBar(
      {required this.filter, required this.groups, required this.onPick});

  final String? filter;
  final List<Group> groups;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opts = [
      (null, 'All'),
      ('open', 'Open'),
      ('verifying', 'Verifying'),
      ('locked', 'Locked'),
      ('done', 'Verified'),
      for (final g in groups) ('g:${g.id}', g.name),
    ];
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        const SizedBox(width: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.only(right: 6, top: 8),
          child: AnimatedAppIcon(
              type: AppIconType.filter,
              active: filter != null,
              size: 18,
              color: filter != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
        ),
        for (final (v, label) in opts)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 8),
            child: _Chip(
              label: label,
              filled: filter == v,
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(v);
              },
            ),
          ),
        if (filter != null)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 8),
            child: _Chip(
              label: 'Clear ✕',
              onTap: () => onPick(null),
            ),
          ),
      ]),
    );
  }
}

/// Collapsible group section — header (dot + name + count + chevron) over a
/// staggered list of rows.
class _GroupSection extends StatefulWidget {
  const _GroupSection({
    required this.group,
    required this.tasks,
    required this.collapsedInitially,
  });
  final Group? group;
  final List<Task> tasks;
  final bool collapsedInitially;

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  late bool _open = !widget.collapsedInitially;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.group;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (g != null)
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _open = !_open);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxs),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: g.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(g.name,
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: AppSpacing.xxs),
              Text('${widget.tasks.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              AnimatedAppIcon(
                  type: AppIconType.chevron,
                  active: _open,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      AnimatedSize(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        child: _open
            ? Column(children: [
                for (var i = 0; i < widget.tasks.length; i++)
                  FadeSlideIn(
                    index: i,
                    stagger: const Duration(milliseconds: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xxs),
                      child: _TaskRow(task: widget.tasks[i]),
                    ),
                  ),
              ])
            : const SizedBox.shrink(),
      ),
    ]);
  }
}

/// Row: swipe right → "Prove it" opens evidence; long-swipe past → rubber-band
/// "Nice try. Proof first."; swipe left → delete with undo + trash anim.
class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({required this.task});
  final Task task;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _rubber;
  bool _showNope = false;

  static const _proveAt = 88.0; // swipe-right reveal threshold
  static const _nopeAt = 220.0; // long-swipe "nice try" threshold

  @override
  void initState() {
    super.initState();
    _rubber = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _dx = _rubber.value);
      });
  }

  @override
  void dispose() {
    _rubber.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dx += d.primaryDelta!;
      if (_dx > _nopeAt) {
        // Rubber-band past the "prove" threshold — resists hard.
        _dx = _nopeAt + (_dx - _nopeAt) * 0.25;
      }
      if (_dx < -160) _dx = -160 + (_dx + 160) * 0.4;
    });
    if (_dx > _proveAt && !_showNope) {
      HapticFeedback.selectionClick();
      _showNope = _dx > _nopeAt;
    }
  }

  void _onDragEnd() {
    final task = widget.task;
    if (_dx > _nopeAt) {
      // Hard long-swipe — playful refusal.
      HapticFeedback.heavyImpact();
      setState(() => _showNope = true);
      _springBack();
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _showNope = false);
      });
    } else if (_dx > _proveAt) {
      // Prove it → evidence sheet.
      _springBack();
      EvidenceSheet.show(context, task);
    } else if (_dx < -70) {
      // Delete with undo.
      _delete();
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _rubber.animateWith(SpringSimulation(
        AppMotion.spring, _dx, 0, 0));
  }

  void _delete() {
    final t = widget.task;
    ref.read(tasksProvider.notifier).deleteTask(t.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Task deleted'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(tasksProvider.notifier).restoreTask(t)),
    ));
    setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.task;
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: (_) => _onDragEnd(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          // Revealed action layers.
          Positioned.fill(
            child: Row(children: [
              if (_dx > 0)
                Container(
                  width: _dx.clamp(0.0, _nopeAt + 30),
                  color: _showNope
                      ? theme.colorScheme.error.withValues(alpha: 0.2)
                      : theme.colorScheme.primary.withValues(alpha: 0.15),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: AppSpacing.md),
                  child: Text(
                    _showNope ? 'Nice try. Proof first.' : 'Prove it →',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: _showNope
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary),
                  ),
                ),
              const Spacer(),
              if (_dx < 0)
                Container(
                  width: (-_dx).clamp(0.0, 160.0),
                  color: theme.colorScheme.error.withValues(alpha: 0.2),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: AnimatedAppIcon(
                      type: AppIconType.trash,
                      active: _dx < -70,
                      size: 20,
                      color: theme.colorScheme.error),
                ),
            ]),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: TaskCard(
              task: t,
              groupName: ref
                  .watch(groupsProvider)
                  .where((g) => g.id == t.groupId)
                  .firstOrNull
                  ?.name,
              accountabilityPending: t.status != TaskStatus.locked &&
                  ref.watch(anyLockedProvider),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => TaskDetailScreen(taskId: t.id))),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Animated integrity-score counter.
class _IntegrityChip extends ConsumerWidget {
  const _IntegrityChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(integrityScoreProvider);
    final theme = Theme.of(context);
    return Chip(
      avatar: AnimatedAppIcon(
          type: AppIconType.shield,
          active: score > 50,
          size: 16,
          color: theme.colorScheme.primary),
      label: Text('$score', style: theme.textTheme.labelLarge),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
    );
  }
}

/// Receipt unroll empty state.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedAppIcon(
            type: AppIconType.receipt,
            active: true,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppSpacing.md),
        Text('Nothing to prove yet', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Add a task — it only counts once the evidence checks out.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}
