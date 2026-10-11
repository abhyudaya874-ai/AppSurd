import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../arena/arena_state.dart';
import '../home/home_screen.dart';
import '../model_picker/model_selection.dart';
import '../playground/playground_screen.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';
import '../tasks/tasks_tab_screen.dart';

/// The visible tab — writable so any screen can switch tabs (Create Task
/// jumps to Tasks after save) without a navigator hack.
final shellTabProvider = NotifierProvider<ShellTabNotifier, int>(
  ShellTabNotifier.new,
);

class ShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Switches the visible tab (0–4).
  void set(int v) => state = v;
}

/// Id of a freshly created task — the Tasks tab pulses its row once so the
/// user sees where it landed.
final highlightedTaskProvider =
    NotifierProvider<HighlightedTaskNotifier, String?>(
      HighlightedTaskNotifier.new,
    );

class HighlightedTaskNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets (or clears) the highlighted task id.
  void set(String? v) => state = v;
}

/// The app's persistent shell — 5 fixed tabs in an IndexedStack (state is
/// preserved per tab) with a glass pill bar pinned to the bottom safe area.
/// Always 5 slots: no conditional tabs, no center orb (mic lives in the
/// Home composer and evidence sheet instead).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _tabCount = 5;

  @override
  void initState() {
    super.initState();
    // Arena persisted on but lineup is empty (pre-seeding installs) — seed
    // once so Arena stays reachable from Ask/Profile.
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

  @override
  Widget build(BuildContext context) {
    var tab = ref.watch(shellTabProvider).clamp(0, _tabCount - 1);
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    const pages = [
      HomeScreen(),
      TasksTabScreen(),
      ScheduleScreen(),
      PlaygroundScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      // Content extends behind the floating bar; each tab pads its own
      // scrollables by the bar height.
      extendBody: true,
      body: TweenAnimationBuilder<double>(
        key: ValueKey(tab),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.standard,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: IndexedStack(index: tab, children: pages),
      ),
      bottomNavigationBar: AnimatedSlide(
        offset: kbOpen ? const Offset(0, 1.5) : Offset.zero,
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.standard,
        child: RepaintBoundary(
          child: _GlassTabBar(
            index: tab,
            onSelect: (i) {
              if (i != tab) HapticFeedback.selectionClick();
              ref.read(shellTabProvider.notifier).set(i);
            },
          ),
        ),
      ),
    );
  }
}

/// One tab slot descriptor — Material icon + label. Custom-painted icons
/// proved invisible in the inactive state, so the bar uses stock icons with
/// a scale/colour animation instead (always legible).
class _TabSpec {
  const _TabSpec(this.icon, this.label);
  final IconData icon;
  final String label;
}

const _tabSpecs = [
  _TabSpec(Icons.home_rounded, 'Home'),
  _TabSpec(Icons.checklist_rounded, 'Tasks'),
  _TabSpec(Icons.calendar_month_rounded, 'Schedule'),
  _TabSpec(Icons.chat_bubble_outline_rounded, 'Ask'),
  _TabSpec(Icons.person_outline_rounded, 'Profile'),
];

/// The fixed full-width glass bar: a highlight blob stretches to the tapped
/// slot (position = width/5 × index), active slot shows icon + label.
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final pad = MediaQuery.paddingOf(context).bottom;

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
                color: theme.colorScheme.outline.withValues(alpha: 0.6),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final slotW = c.maxWidth / _tabSpecs.length;
                return Stack(
                  children: [
                    // Stretching highlight blob — centred on the active slot.
                    AnimatedPositioned(
                      duration: AppMotion.of(
                        context,
                        const Duration(milliseconds: 350),
                      ),
                      curve: Curves.easeOutBack,
                      left: slotW * index + 4,
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
                    Row(
                      children: [
                        for (var i = 0; i < _tabSpecs.length; i++)
                          Expanded(
                            child: _TabSlot(
                              spec: _tabSpecs[i],
                              active: i == index,
                              onTap: () => onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '${spec.label} tab',
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: active ? 1.1 : 1.0,
                duration: AppMotion.of(context, AppMotion.fast),
                curve: AppMotion.standard,
                child: Icon(spec.icon, size: 21, color: color),
              ),
              // Label expands beside the active icon.
              ClipRect(
                child: AnimatedSize(
                  duration: AppMotion.of(context, AppMotion.base),
                  curve: AppMotion.standard,
                  child: active
                      ? Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            spec.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: color,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
