import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../arena/arena_state.dart';
import '../model_picker/model_selection.dart';
import '../playground/playground_screen.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_list_screen.dart';
import '../voice/voice_overlay.dart';

/// The app's persistent shell — content tabs in an IndexedStack (state is
/// preserved per tab) with a floating glass pill bar that slides a stretched
/// highlight blob between tabs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Arena persisted on but lineup is empty (pre-seeding installs) — seed
    // once so the Arena tab can appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = ref.read(modelSelectionProvider);
      if (sel.arenaMode && sel.arenaLineup.length < 2) {
        final n = ref.read(modelSelectionProvider.notifier);
        for (final id in defaultLineup()) {
          n.toggleArenaModel(id);
        }
      }
    });
  }
  List<({AppIconType icon, String label, Widget page})> get _tabs => [
        (
          icon: AppIconType.tasks,
          label: 'Tasks',
          page: const TaskListScreen(),
        ),
        (
          icon: AppIconType.ask,
          label: 'Ask',
          page: const PlaygroundScreen(),
        ),
        // Arena tab exists only when a lineup is selected.
        if (ref.watch(arenaReadyProvider))
          (
            icon: AppIconType.arena,
            label: 'Arena',
            page: const _ArenaTab(),
          ),
        (
          icon: AppIconType.settings,
          label: 'Settings',
          page: const SettingsScreen(),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (_tab >= tabs.length) _tab = 0; // arena tab hid → clamp
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      extendBody: true, // tab bar floats over content
      body: IndexedStack(
        index: _tab,
        children: [for (final t in tabs) t.page],
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedSlide(
        offset: kbOpen ? const Offset(0, 2) : Offset.zero,
        duration: AppMotion.base,
        child: RepaintBoundary(child: _FloatingTabBar(
          tabs: tabs,
          index: _tab,
          onSelect: (i) {
            HapticFeedback.selectionClick();
            setState(() => _tab = i);
          },
          onOrb: () => VoiceOrbButton.show(context,
              intent: VoiceIntent.task),
        )),
      ),
    );
  }
}

/// Arena tab content — explained below in `_ArenaTab`. Kept minimal: the
/// lineup, a free "does this hold up?" prompt is out of scope; the tab
/// surfaces the lineup + last verdicts so the jury is discoverable.
class _ArenaTab extends ConsumerWidget {
  const _ArenaTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lineup = ref.watch(arenaLineupProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Arena')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Jury of ${lineup.length}',
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final m in lineup)
              Text(
                '${m.provider.label} · ${m.displayName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Submit proof on a task while Arena is on — every judge '
              'votes, and the verdict is computed in code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ]),
        ),
      ),
    );
  }
}

/// The floating glass bar: highlight blob stretches toward the tapped tab,
/// active tab's label expands beside its icon.
class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.tabs,
    required this.index,
    required this.onSelect,
    required this.onOrb,
  });

  final List<({AppIconType icon, String label, Widget page})> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onOrb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final pad = MediaQuery.paddingOf(context).bottom;

    // Slots: tabs split by the center orb button.
    final slotCount = tabs.length + 1;
    final orbAt = (slotCount / 2).floor();

    return Padding(
      padding: EdgeInsets.only(bottom: pad + 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 62,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.6)),
            ),
            child: LayoutBuilder(builder: (context, c) {
              final slotW = c.maxWidth / slotCount;
              // Blob position: which slot the active tab occupies.
              final blobX = slotW * (index < orbAt ? index : index + 1);
              return Stack(children: [
                // Stretching highlight blob.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  left: blobX + 4,
                  top: 6,
                  bottom: 6,
                  width: slotW - 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < slotCount; i++)
                    if (i == orbAt)
                      SizedBox(
                        width: slotW,
                        child: Center(child: _OrbButton(onTap: onOrb)),
                      )
                    else
                      SizedBox(
                        width: slotW,
                        child: _TabSlot(
                          icon: tabs[i < orbAt ? i : i - 1].icon,
                          label: tabs[i < orbAt ? i : i - 1].label,
                          active: (i < orbAt ? i : i - 1) == index,
                          onTap: () => onSelect(i < orbAt ? i : i - 1),
                        ),
                      ),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final AppIconType icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedAppIcon(
              type: icon, active: active, size: 21, color: color),
          // Label expands beside the active icon.
          ClipRect(
            child: AnimatedSize(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              child: active
                  ? Padding(
                      padding:
                          const EdgeInsets.only(left: AppSpacing.xxs),
                      child: Text(label,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: color)),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Raised center orb — opens the voice overlay (phase 5b wired it).
class _OrbButton extends StatelessWidget {
  const _OrbButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        transform: Matrix4.translationValues(0, -6, 0), // raised
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 16,
            ),
          ],
        ),
        child: const Icon(Icons.mic, color: Colors.black, size: 22),
      ),
    );
  }
}
