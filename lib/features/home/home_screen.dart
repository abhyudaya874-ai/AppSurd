import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../../core/widgets/pressable.dart';
import '../model_picker/model_pill.dart';
import '../playground/playground_screen.dart' show askSeedProvider;
import '../shell/app_shell.dart';
import '../tasks/composer_hero.dart';
import '../tasks/create_task_screen.dart';
import '../tasks/group_model.dart';
import '../tasks/group_picker.dart';
import '../tasks/tasks_provider.dart';
import '../voice/voice_overlay.dart';

/// Home — Perplexity-style: top bar (avatar / Task·Ask segment pill /
/// integrity button), a centred brand mark + serif tagline + suggestion
/// chips, and the composer pinned to the bottom above the keyboard.
/// Sending flies the text into Create Task (Task mode) or seeds the Ask
/// composer (Ask mode).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();
  String? _groupId; // null = Inbox
  DateTime? _dueAt;
  final _images = <XFile>[];
  bool _askMode = false; // centre pill: Task (default) vs Ask

  static const _suggestions = [
    'Finish an assignment',
    'Push a commit',
    'Read 20 pages',
    'Gym session',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {})); // drives the send-icon swap
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Task mode → fly the text into Create Task; Ask mode → seed the Ask
  /// composer and switch destination.
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      // Empty = voice input, mirroring Perplexity's waveform button.
      await VoiceOrbButton.show(context, intent: VoiceIntent.task).then((r) {
        if (r != null) {
          _ctrl.text = r.text;
          _ctrl.selection = TextSelection.collapsed(offset: r.text.length);
        }
      });
      return;
    }
    FocusScope.of(context).unfocus();
    if (_askMode) {
      ref.read(askSeedProvider.notifier).set(text);
      ref.read(navIndexProvider.notifier).set(3);
      _ctrl.clear();
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      createTaskRoute(
        text,
        initialGroupId: _groupId,
        initialDueAt: _dueAt,
        attachmentPaths: [for (final f in _images) f.path],
      ),
    );
    if (saved == true) {
      _ctrl.clear();
      setState(() {
        _dueAt = null;
        _images.clear();
      });
    }
  }

  /// The "+" sheet: pick a group, set a due date, or attach an image.
  Future<void> _plusSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Group'),
              subtitle: Text(_groupName()),
              onTap: () async {
                Navigator.pop(context);
                final g = await pickGroupSheet(this.context, ref);
                if (g != null) {
                  setState(() => _groupId = g.isEmpty ? null : g);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('Due date'),
              subtitle: Text(_dueLabel),
              onTap: () async {
                Navigator.pop(context);
                await _pickDue();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Add image'),
              onTap: () async {
                Navigator.pop(context);
                final f = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1600,
                );
                if (f != null) setState(() => _images.add(f));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _groupName() =>
      ref
          .read(groupsProvider)
          .where((g) => g.id == _groupId)
          .firstOrNull
          ?.name ??
      'Inbox';

  String get _dueLabel {
    final d = _dueAt;
    if (d == null) return 'None';
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d == null) return;
    setState(() => _dueAt = DateTime(d.year, d.month, d.day, 18));
  }

  Future<void> _pickGroupQuick() async {
    final g = await pickGroupSheet(context, ref);
    if (g != null) setState(() => _groupId = g.isEmpty ? null : g);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typing = _ctrl.text.trim().isNotEmpty;

    return Scaffold(
      // Body resizes with the keyboard so the pinned composer glides up.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ConstrainedContent(
          child: Column(
            children: [
              // ---- Top bar ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  0,
                ),
                child: Row(
                  children: [
                    const MenuAvatar(size: 40),
                    const Spacer(),
                    _ModePill(
                      askMode: _askMode,
                      onChanged: (v) => setState(() => _askMode = v),
                    ),
                    const Spacer(),
                    _IntegrityButton(
                      onTap: () => ref.read(navIndexProvider.notifier).set(4),
                    ),
                  ],
                ),
              ),

              // ---- Centre: mark + tagline + suggestions ----
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeSlideIn(
                          child: AnimatedAppIcon(
                            type: AppIconType.receipt,
                            active: true,
                            size: 56,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Receipts',
                          style: AppTypography.grotesk(
                            theme.colorScheme.onSurface,
                          ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'What will you prove today?',
                          textAlign: TextAlign.center,
                          style: AppTypography.display(
                            theme.colorScheme.onSurfaceVariant,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // Suggestions fade away while typing.
                        AnimatedOpacity(
                          opacity: typing ? 0 : 1,
                          duration: AppMotion.of(context, AppMotion.fast),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              for (final s in _suggestions)
                                AppChip(
                                  label: s,
                                  onTap: () {
                                    _ctrl.text = s;
                                    _ctrl.selection = TextSelection.collapsed(
                                      offset: s.length,
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---- Composer pinned to bottom ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: _buildComposer(theme, typing),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme, bool typing) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attached images strip.
          if (_images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: _ImageThumb(
                          path: _images[i].path,
                          onRemove: () => setState(() => _images.removeAt(i)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Row 1 — the field. Its Hero shares 'composer-text' with Create
          // Task's title so the text physically flies up.
          Hero(
            tag: kComposerHeroTag,
            flightShuttleBuilder: composerTextShuttle,
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _askMode ? 'Ask anything…' : 'Add a task…',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
              ),
            ),
          ),
          // Row 2 — + / model chip / group / mic / send.
          Row(
            children: [
              _GhostRound(
                icon: Icons.add_rounded,
                tooltip: 'Group, due date, image',
                onTap: _plusSheet,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Flexible(child: ModelPill()),
              const Spacer(),
              _GhostIcon(
                icon: Icons.inbox_outlined,
                tooltip: 'Group: ${_groupName()}',
                onTap: _pickGroupQuick,
              ),
              const SizedBox(width: AppSpacing.xxs),
              VoiceOrbButton(
                intent: VoiceIntent.task,
                onResult: (r) {
                  _ctrl.text = r.text;
                  _ctrl.selection = TextSelection.collapsed(
                    offset: r.text.length,
                  );
                },
              ),
              const SizedBox(width: AppSpacing.xxs),
              // 40dp white round button — waveform when empty (voice),
              // arrow-up when there's text (send).
              Pressable(
                onTap: _send,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.onSurface,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.fast),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: RotationTransition(
                        turns: Tween(begin: 0.5, end: 1.0).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      typing
                          ? Icons.arrow_upward_rounded
                          : Icons.graphic_eq_rounded,
                      key: ValueKey(typing),
                      color: theme.colorScheme.surface,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small rounded-square ghost button used for the composer's "+" affordance.
class _GhostRound extends StatelessWidget {
  const _GhostRound({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Plain icon button with the same quiet treatment.
class _GhostIcon extends StatelessWidget {
  const _GhostIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 19,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Centre segmented pill — two icon buttons (Task / Ask) with an animated
/// selected segment.
class _ModePill extends StatelessWidget {
  const _ModePill({required this.askMode, required this.onChanged});
  final bool askMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            context,
            theme,
            Icons.edit_note_rounded,
            !askMode,
            () => onChanged(false),
            'Task mode',
          ),
          _seg(
            context,
            theme,
            Icons.chat_bubble_outline_rounded,
            askMode,
            () => onChanged(true),
            'Ask mode',
          ),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    bool on,
    VoidCallback tap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: tap,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          width: 52,
          height: 32,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: on
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 18,
            color: on
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Top-right rounded-square button: integrity shield + score → Profile.
class _IntegrityButton extends ConsumerWidget {
  const _IntegrityButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final score = ref.watch(integrityScoreProvider);
    return Tooltip(
      message: 'Integrity $score — Profile',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedAppIcon(
                type: AppIconType.shield,
                active: score > 50,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              Text(
                '$score',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded thumbnail for an attached image, with an ✕ remove.
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: -4,
          top: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Icon(
                Icons.close,
                size: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// File-backed thumbnail (dart:io is safe — Android-first target).
