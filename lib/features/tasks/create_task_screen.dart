import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/app_chip.dart';
import '../shell/app_shell.dart';
import 'composer_hero.dart';
import 'group_model.dart';
import 'group_picker.dart';
import 'tasks_provider.dart';

/// Pushes Create Task with the composer→title shared-element flight. The
/// page fades/slides up slowly (hero-slow) while the Hero carries the text.
PageRouteBuilder<bool> createTaskRoute(
  String initialTitle, {
  String? initialGroupId,
  DateTime? initialDueAt,
  List<String> attachmentPaths = const [],
}) {
  return PageRouteBuilder<bool>(
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.slow,
    pageBuilder: (context, animation, secondary) => CreateTaskScreen(
      initialTitle: initialTitle,
      initialGroupId: initialGroupId,
      initialDueAt: initialDueAt,
      attachmentPaths: attachmentPaths,
    ),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Full task editor reached by flying the composer's text into the title
/// field: proof prompt, group, due date/time, priority, estimated duration.
/// Pops with `true` when a task was saved (so the composer can clear itself).
class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({
    super.key,
    required this.initialTitle,
    this.initialGroupId,
    this.initialDueAt,
    this.attachmentPaths = const [],
  });

  final String initialTitle;
  final String? initialGroupId;
  final DateTime? initialDueAt;

  /// Image paths attached in the composer — shown as a reminder chip row so
  /// they can be re-attached as evidence later.
  final List<String> attachmentPaths;

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  late final TextEditingController _title;
  late final TextEditingController _proof;
  final _titleFocus = FocusNode();
  String? _groupId;
  DateTime? _dueAt;
  int _priority = 0;
  int? _durationMin;
  bool _saving = false;

  static const _durations = [15, 30, 60, 90, 120];
  static const _priorities = ['None', 'Med', 'High'];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
    _proof = TextEditingController();
    _groupId = widget.initialGroupId;
    _dueAt = widget.initialDueAt;
    // Focus only after the Hero flight finishes — an early keyboard would
    // jank the shared-element animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      final anim = route?.animation;
      if (anim == null || anim.status == AnimationStatus.completed) {
        _titleFocus.requestFocus();
      } else {
        void onStatus(AnimationStatus s) {
          if (s == AnimationStatus.completed && mounted) {
            _titleFocus.requestFocus();
            anim.removeStatusListener(onStatus);
          }
        }

        anim.addStatusListener(onStatus);
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _proof.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d == null) return;
    setState(
      () => _dueAt = DateTime(
        d.year,
        d.month,
        d.day,
        _dueAt?.hour ?? 18,
        _dueAt?.minute ?? 0,
      ),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? DateTime.now()),
    );
    if (t == null) return;
    final base = _dueAt ?? DateTime.now();
    setState(
      () =>
          _dueAt = DateTime(base.year, base.month, base.day, t.hour, t.minute),
    );
  }

  String get _dueLabel {
    final d = _dueAt;
    if (d == null) return 'Due date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final dayLabel = day == today
        ? 'Today'
        : day == today.add(const Duration(days: 1))
        ? 'Tomorrow'
        : '${d.day}/${d.month}/${d.year}';
    return '$dayLabel · ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    final task = await ref
        .read(tasksProvider.notifier)
        .addTask(
          title: title,
          description: _proof.text.trim(),
          groupId: _groupId,
          dueAt: _dueAt,
          priority: _priority,
          durationMin: _durationMin,
        );
    // Land in the Tasks tab with the new row highlighted.
    ref.read(highlightedTaskProvider.notifier).set(task.id);
    ref.read(navIndexProvider.notifier).set(1);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = ref
        .watch(groupsProvider)
        .where((g) => g.id == _groupId)
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Back without saving',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'NEW TASK',
                style: AppTypography.sectionLabel(theme.colorScheme.primary),
              ),
              const SizedBox(height: AppSpacing.xs),
              // The Hero target: text flies in here at 28sp.
              Hero(
                tag: kComposerHeroTag,
                flightShuttleBuilder: composerTextShuttle,
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontSize: 28,
                      height: 1.2,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Task title',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _proof,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'What counts as proof?',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: theme.textTheme.bodyLarge,
              ),
              if (widget.attachmentPaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final p in widget.attachmentPaths)
                        Chip(
                          avatar: const Icon(Icons.image_outlined, size: 14),
                          label: Text(
                            p.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppChip(
                    label: group?.name ?? 'Inbox',
                    trailing: Icon(
                      Icons.expand_more,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () async {
                      final g = await pickGroupSheet(context, ref);
                      if (g != null) {
                        setState(() => _groupId = g.isEmpty ? null : g);
                      }
                    },
                  ),
                  AppChip(
                    label: _dueLabel,
                    filled: _dueAt != null,
                    leading: Icon(
                      Icons.event_rounded,
                      size: 14,
                      color: _dueAt != null
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    trailing: _dueAt != null
                        ? GestureDetector(
                            onTap: () => setState(() => _dueAt = null),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.expand_more,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    onTap: _pickDate,
                  ),
                  if (_dueAt != null)
                    AppChip(label: 'Set time', onTap: _pickTime),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Priority',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  for (var i = 0; i < _priorities.length; i++) ...[
                    AppChip(
                      label: _priorities[i],
                      filled: _priority == i,
                      onTap: () => setState(() => _priority = i),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Estimated duration',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final m in _durations)
                    AppChip(
                      label: m >= 60
                          ? '${m ~/ 60}h${m % 60 > 0 ? ' ${m % 60}m' : ''}'
                          : '${m}m',
                      filled: _durationMin == m,
                      onTap: () => setState(
                        () => _durationMin = _durationMin == m ? null : m,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
